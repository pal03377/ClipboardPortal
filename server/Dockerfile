FROM python:3.12
WORKDIR /code
COPY ./requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt
CMD python -Xfrozen_modules=off -u -m debugpy --listen 0.0.0.0:$PY_DEBUG_PORT -m uvicorn app.main:app --proxy-headers --host 0.0.0.0 --port $PORT --reload
