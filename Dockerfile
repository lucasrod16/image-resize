FROM cgr.dev/chainguard/static:latest

COPY build/image-resize-lambda /image-resize-lambda

CMD ["/image-resize-lambda"]
