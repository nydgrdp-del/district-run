FROM python:3.12-slim
WORKDIR /app
COPY server/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && useradd -m game
COPY server ./server
COPY client/data ./client/data
RUN mkdir /data && chown game:game /data
USER game
ENV HOST=0.0.0.0 PORT=8765 DISTRICT_DB=/data/district.sqlite3
EXPOSE 8765
CMD ["python", "server/app.py"]
