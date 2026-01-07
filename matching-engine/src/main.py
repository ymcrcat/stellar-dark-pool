import os
import uvicorn
from .config import settings

def main():
    tls_cert = os.getenv("TLS_CERT_PATH")
    tls_key = os.getenv("TLS_KEY_PATH")
    use_tls = bool(tls_cert and tls_key and os.path.exists(tls_cert) and os.path.exists(tls_key))

    uvicorn.run(
        "src.api:app",
        host="0.0.0.0",
        port=settings.rest_port,
        reload=False,
        ssl_certfile=tls_cert if use_tls else None,
        ssl_keyfile=tls_key if use_tls else None,
    )

if __name__ == "__main__":
    main()
