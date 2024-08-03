from fastapi import FastAPI, UploadFile, File, Form, HTTPException, WebSocket
from starlette.websockets import WebSocketDisconnect
from pydantic import BaseModel

import logging
import sys
from uuid import uuid4
import secrets
import os
import glob
from datetime import datetime

from watchfiles import awatch # watchfiles for notifying client when new clipboard content is available

# - For each user, there is one file <user_id>_<secret>: Contains the last clipboard content received by the user (just the file or "text:<some text>" for text content)
# - Create user: Creates empty file in ./data/<user_id>_<secret>
# - Send clipboard content: Writes clipboard content to ./data/<user_id>_<secret> (file directly or "text:<some text>")
# - Detect clipboard content: WebSocket endpoint that receives an initial message with {"id": "<user id>", "secret": "<user secret>", "date": "2024-01-01T00:00:00Z"} for auth and change detection and then sends an event as soon as the file date is newer until the connection is broken
# - Download clipboard content: Directly download the static file (does not involve the Python server)


app = FastAPI()

# Logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
stream_handler = logging.StreamHandler(sys.stdout)
log_formatter = logging.Formatter("%(asctime)s [%(processName)s: %(process)d] [%(threadName)s: %(thread)d] [%(levelname)s] %(name)s: %(message)s")
stream_handler.setFormatter(log_formatter)
logger.addHandler(stream_handler)
logger.info("Starting server")

data_dir = os.environ.get("DATA_DIR", "data")

# Route to check that server works
@app.get("/")
async def root():
    return {"message": "clipboardportal"}

# Create user: POST /users -> {"id": "12345678", "secret": "ab8902d2-75c1-4dec-baae-1f5ee859e0c7"}
class UserCreateResponse(BaseModel):
    id: str     # 8-digit user id, e.g. "12345678"
    secret: str # Secret, e.g. "ab8902d2-75c1-4dec-baae-1f5ee859e0c7"
def get_user_data_file(user_id): # Get file path for user data, e.g. "./data/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7" or None (user does not exist)
    files = glob.glob(f"{data_dir}/{user_id}_*") # Get all files for user id, e.g. ["./data/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7"]
    if files: return files[0] # Return only file for user id if it exists, e.g. "./data/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7"
    else: return None # Return None if user does not exist
@app.post("/users")
async def create_user() -> UserCreateResponse:
    user_id = None
    while user_id is None or get_user_data_file(user_id) is not None: # Generate new user id until it is unique
        user_id = str(secrets.choice(range(0, 99999999))).zfill(8) # Create 8-digit user id, e.g. 12345678
    secret = str(uuid4()) # Generate secret, e.g. ab8902d2-75c1-4dec-baae-1f5ee859e0c7
    open(f"{data_dir}/{user_id}_{secret}", "w").close() # Create empty file for user, e.g. ./data/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7
    return UserCreateResponse(id=user_id, secret=secret) # Return user id and secret for the app, e.g. {"id": "12345678", "secret": "ab8902d2-75c1-4dec-baae-1f5ee859e0c7"}


# Send clipboard to another user: POST /send {"receiverId": "12345678"} with file upload -> empty response
def is_valid_user_id(user_id): return user_id.isdigit() and len(user_id) == 8 # Check if user id is valid for security, e.g. "12345678"
@app.post("/send")
async def send_clipboard_content(receiverId: str = Form(...), file: UploadFile = File(...)) -> None:
    if not is_valid_user_id(receiverId): raise HTTPException(status_code=404, detail="User not found")
    user_data_file = get_user_data_file(receiverId) # Get file path for user data, e.g. "./data/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7" or None (user does not exist)
    if user_data_file is None: raise HTTPException(status_code=404, detail="User not found")
    # Save uploaded file to ./data/<receiver_id>_*
    with open(user_data_file, "wb") as f: f.write(await file.read()) # Save uploaded file to user data file


# Detect clipboard changes for current user: WebSocket /ws {"id": "12345678", "secret": "ab8902d2-75c1-4dec-baae-1f5ee859e0c7", "date": "2024-01-01T00:00:00Z"} -> Get message "new" when clipboard content changes
@app.websocket("/ws")
async def detect_clipboard_content(websocket: WebSocket):
    logger.info("Waiting for WS accept...")
    await websocket.accept() # Accept WebSocket connection
    try:
        logger.info("Waiting for auth...")
        auth_data = await websocket.receive_json() # Receive auth data from client, e.g. {"id": "12345678", "secret": "ab8902d2-75c1-4dec-baae-1f5ee859e0c7", "date": "2024-01-01T00:00:00Z"}
    except WebSocketDisconnect: return # No error if client disconnects
    logger.info("Received authentication %s", auth_data)
    user_data_file = f"{data_dir}/{auth_data['id']}_{auth_data['secret']}" # Get file path for user data based on secret, e.g. "./data/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7"
    if not os.path.exists(user_data_file): raise HTTPException(status_code=403, detail="Unauthorized") # Abort if user data file does not exist (wrong user ID or wrong secret)
    logger.info("Authenticated! %s", auth_data["id"])
    last_change_date = datetime.fromisoformat(auth_data["date"]) # Get last change date from client, e.g. 2024-01-01 00:00:00+00:00
    logger.info("Waiting for changes...")
    try:
        async for _ in awatch(user_data_file): # On every file change
            logger.info("Change for user %s", auth_data["id"])
            if os.path.getmtime(user_data_file) > last_change_date.timestamp(): # If file was changed after last change date
                logger.info("Sending new clipboard contents")
                await websocket.send_text("new") # Send "new" to client
                last_change_date = datetime.now() # Update last change date to current date
        await websocket.close() # Close WebSocket connection when done
    except WebSocketDisconnect: return # No error if client disconnects


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
