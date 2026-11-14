# Brieflee knowledge service (full-text RAG over the knowledge layer).
FROM python:3.12-slim
WORKDIR /app
COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r server/requirements.txt
COPY server/ server/
# knowledge.db is large, so it is downloaded at start-up from KNOWLEDGE_DB_URL
# (for example the asset attached to the repository's GitHub Release).
ENV KNOWLEDGE_DB=/data/knowledge.db
CMD ["sh", "server/start.sh"]
