# Brieflee knowledge service on a Hugging Face Space (Docker, port 7860).
# The database is downloaded from the GitHub release at start-up
# (KNOWLEDGE_DB_PARTS, a Space variable set by the deploy workflow).
FROM python:3.12-slim
RUN useradd -m -u 1000 user
USER user
WORKDIR /home/user/app
COPY --chown=user server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir --user -r server/requirements.txt
ENV PATH=/home/user/.local/bin:$PATH \
    KNOWLEDGE_DB=/tmp/brieflee/knowledge.db \
    PORT=7860
COPY --chown=user server/ server/
CMD ["sh", "server/start.sh"]
