import uvicorn
from .config import settings

def main():
    uvicorn.run(
        "src.api:app",
        host="0.0.0.0",
        port=settings.rest_port,
        reload=False
    )

if __name__ == "__main__":
    main()
