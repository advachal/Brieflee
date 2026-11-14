# Brieflee knowledge service (full-text RAG over the knowledge layer).
FROM python:3.12-slim
WORKDIR /app
COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r server/requirements.txt
COPY server/ server/
COPY knowledge/ knowledge/
# knowledge.db is unpacked at start-up from knowledge/ (or KNOWLEDGE_DB_URL).
ENV KNOWLEDGE_DB=/data/knowledge.db
CMD ["sh", "server/start.sh"]
