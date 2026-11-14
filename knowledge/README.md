# Knowledge layer database

`knowledge.db` (SQLite with an FTS5 index) built from 13,241 Delhi High Court
judgments (2023 to 2025). Source: AWS Open Data, Indian High Court Judgments
(CC BY 4.0). It is gzipped and split to stay under GitHub's file size limit.

Rebuild the file:

    cat knowledge/knowledge.db.gz.part-* | gunzip > build/knowledge/knowledge.db

SHA-256 of the joined .gz: 14433bd37b07e8514efa5c67010e5c864bceb3fe92dc08c9eb26a6bd766071a7

The server (`server/start.sh`) does this automatically. To regenerate from
scratch, run `tool/knowledge/harvest_texts.py` then `tool/knowledge/build_knowledge.py`.
