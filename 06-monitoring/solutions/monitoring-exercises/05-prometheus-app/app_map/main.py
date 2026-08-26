from pathlib import Path

from fastapi import FastAPI, Response
from fastapi.staticfiles import StaticFiles
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from .api.endpoints import router as item_router

app = FastAPI()

app.include_router(item_router)

@app.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(
        content=generate_latest(),
        headers={"Content-Type": CONTENT_TYPE_LATEST},
    )

# Resolve the statics directory relative to this file so it does not depend on
# the current working directory from which Uvicorn is launched.
statics_dir = Path(__file__).resolve().parent / "statics"
app.mount("/", StaticFiles(directory=str(statics_dir), html=True), name="static")
