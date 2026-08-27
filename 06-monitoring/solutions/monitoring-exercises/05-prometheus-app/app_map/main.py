from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from prometheus_client import make_asgi_app

from .api.endpoints import router as item_router

app = FastAPI()

app.include_router(item_router)

metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)


@app.get("/metrics", include_in_schema=False)
def redirect_metrics_to_canonical_endpoint() -> RedirectResponse:
    return RedirectResponse(url="/metrics/")


# Resolve the statics directory relative to this file so it does not depend on
# the current working directory from which Uvicorn is launched.
statics_dir = Path(__file__).resolve().parent / "statics"
app.mount("/", StaticFiles(directory=str(statics_dir), html=True), name="static")
