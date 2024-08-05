from fastapi import FastAPI, Form, UploadFile, File, HTTPException, WebSocket
from starlette.websockets import WebSocketDisconnect
from pydantic import BaseModel, ValidationError
from watchfiles import awatch # watchfiles for notifying client when new clipboard content is available

import logging
import json
import sys
import secrets
import os
import asyncio

# - For each user, there is one file <user_id>: Contains the last clipboard content received by the user (just the file for files or "<some text>" for text content)
# - Create user: Creates empty files in ./data/<user_id>, ./data/<user_id>.meta and writes public key to ./data/<user_id>.publickey for encryption
# - Send clipboard content: Writes clipboard content to ./data/<user_id> and transmitted metadata to ./data/<user_id>.meta including the user's public key for quicker access
# - Detect clipboard content: WebSocket endpoint that receives an initial message with {"id": "<user id>", "date": "2024-01-01T00:00:00Z"} then sends an event as soon as the file date is newer until the connection is broken
# - Download clipboard content: Directly download the static file (does not involve the Python server)
# - Decryption and verification of authenticity: Done on the client


app = FastAPI()

# Logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
stream_handler = logging.StreamHandler(sys.stdout)
log_formatter = logging.Formatter("%(asctime)s [%(processName)s: %(process)d] [%(levelname)s] %(name)s: %(message)s")
stream_handler.setFormatter(log_formatter)
logger.addHandler(stream_handler)
logger.info("Starting server")

data_dir = os.environ.get("DATA_DIR", "data")

# Route to check that server works
@app.get("/")
async def root():
    return {"message": "clipboardportal"}

# Create user: POST /users {"publicKeyBase64": "..."} -> {"id": "12345678"}
class UserCreateRequest(BaseModel):
    publicKeyBase64: str # Base64 of the user's public key
class UserCreateResponse(BaseModel):
    id: str # 8-digit user id, e.g. "12345678"
def get_user_data_file(user_id): # Get file path for user data, e.g. "./data/12345678" or None (user does not exist)
    user_data_file_path = os.path.join(data_dir, user_id) # Get file path for user data, e.g. "./data/12345678"
    if not os.path.exists(user_data_file_path): return None # Return None if user does not exist
    return user_data_file_path # Return file path for user data
@app.post("/users")
async def create_user(create_request: UserCreateRequest) -> UserCreateResponse:
    user_id = None
    while user_id is None or get_user_data_file(user_id) is not None: # Generate new user id until it is unique
        user_id = str(secrets.choice(range(0, 99999999))).zfill(8) # Create 8-digit user id, e.g. 12345678
    open(f"{data_dir}/{user_id}",      "w").close() # Create empty file for clipboard content, e.g. ./data/12345678
    open(f"{data_dir}/{user_id}.meta", "w").close() # Init metadata file next to the content file for change detection
    with open(f"{data_dir}/{user_id}.publickey", "w") as f: f.write(create_request.publicKeyBase64) # Save public key
    return UserCreateResponse(id=user_id) # Return user id for the app, e.g. {"id": "12345678"}


# Send clipboard to another user: POST /send {"receiverId": "12345678"} with file upload -> empty response
def is_valid_user_id(user_id): return user_id.isdigit() and len(user_id) == 8 # Check if user id is valid for security, e.g. "12345678"
# Clipboard content metadata for sending
class ClipboardContentSendMetadata(BaseModel):
    senderId: str # 8-digit user id, e.g. "12345678"
    encryptedContentMetadataBase64: str # Encrypted metadata including content type and filename to store as few unencrypted information as possible
@app.post("/send/{receiver_id}")
async def send_clipboard_content(receiver_id: str, meta: str = Form(...), file: UploadFile = File(...)) -> None:
    try: meta = ClipboardContentSendMetadata.parse_raw(meta) # Parse metadata for clipboard content
    except ValidationError: raise HTTPException(status_code=422, detail="Invalid metadata")
    if not is_valid_user_id(receiver_id): raise HTTPException(status_code=404, detail="User not found")
    user_data_file = get_user_data_file(receiver_id) # Get file path for user data, e.g. "./data/12345678" or None (user does not exist)
    if user_data_file is None: raise HTTPException(status_code=404, detail="User not found")
    # Save uploaded file to ./data/<receiver_id>
    logger.info("Saving file for user %s", receiver_id)
    with open(user_data_file, "wb") as f: f.write(await file.read()) # Save uploaded file to user data file
    # Save metadata for the receiver including the filename for correct filename when downloading. Save metadata last because the send event fires as soon as this file is updated.
    logger.info("Saving metadata for user %s", receiver_id)
    with open(user_data_file + ".meta", "w") as f: # Save metadata file next to user data file
        json.dump(meta.dict(), f)
    os.utime(user_data_file + ".meta", None) # Touch metadata file for change detection below


# Detect clipboard changes for current user: WebSocket /ws {"id": "12345678"} -> Get message with ClipboardContentReceiveMetadata when clipboard content changes
class WebsocketServerMessage(BaseModel):
    event: str # Event type, e.g. "new" or "forbidden"
    meta: ClipboardContentSendMetadata | None # Clipboard content metadata or None
    publicKeyBase64: str | None # Public key (for saving a request on the client to get it) or None
@app.websocket("/ws")
async def detect_clipboard_content(websocket: WebSocket):
    logger.info("Waiting for WS accept...")
    await websocket.accept() # Accept WebSocket connection
    try:
        logger.info("Waiting for initial connect message...")
        connect_message = await websocket.receive_json() # Receive connection message from client, e.g. {"id": "12345678"}
    except WebSocketDisconnect: return # No error if client disconnects before sending the initial connection message
    # TODO: Authenticate? Send "forbidden" event if user is not authenticated
    logger.info("Received connect message %s", connect_message)
    user_data_file = get_user_data_file(connect_message["id"]) # Get file path for content, e.g. "./data/12345678"
    if user_data_file is None: # Abort if user data file does not exist (wrong user ID)
        logger.info("User not found %s", user_data_file)
        await websocket.send_text(json.dumps(WebsocketServerMessage(event="forbidden").dict())) # Send "forbidden" event to client
        await websocket.close() # Close WebSocket connection so that app notices error
        return
    meta_data_file = user_data_file + ".meta"                  # Get file path for meta data, e.g. "./data/12345678.meta"
    logger.info("Authenticated! %s", connect_message["id"])
    logger.info("Waiting for changes...")
    watch_files_stop_event = asyncio.Event() # Event to stop watching files after WebSocket connection is closed
    async def watch_files():
        try:
            async for _ in awatch(meta_data_file, stop_event=watch_files_stop_event): # On every file change
                logger.info("Change for user %s", connect_message["id"])
                logger.info("Sending new clipboard content metadata")
                with open(meta_data_file, "r") as f: metadata = f.read() # Read metadata file for clipboard content, e.g. '{"senderId": "12345678", "type": "text", "filename": null}'
                with open(user_data_file + ".publickey", "r") as f: public_key_base64 = f.read() # Read public key for quick access on the client without another request
                await websocket.send_text(json.dumps(WebsocketServerMessage( # Send new clipboard event to client
                    event="new",
                    meta=ClipboardContentSendMetadata.parse_raw(metadata),
                    publicKeyBase64=public_key_base64
                ).dict()))
        except WebSocketDisconnect: print("WebSocket disconnected")
    asyncio.ensure_future(watch_files()) # Start watching files in background so that a uvicorn reload can stop file watching
    try: await websocket.receive_text() # Wait for client to keep connection alive while watching files in the background
    except WebSocketDisconnect:
        watch_files_stop_event.set() # Stop watching files when client disconnects
        return # No error if client disconnects or uvicorn reload closes the connection
    raise Exception("Client sent a WebSocket message. This is not intended.")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
