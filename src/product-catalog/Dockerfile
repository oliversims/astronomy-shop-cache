FROM golang:1.22-alpine AS builder

WORKDIR /usr/src/app/

# git + CAs: Alpine's Go image omits them. Some modules (buf.build)
# fall back to git when proxy.golang.org is slow or misses a path.
RUN apk add --no-cache ca-certificates git

ENV GOPROXY=https://proxy.golang.org,direct \
    GOSUMDB=sum.golang.org

COPY go.mod go.sum ./

# proxy.golang.org / buf.build can flake on GitHub Actions BuildKit.
RUN for i in 1 2 3 4 5; do \
      go mod download && exit 0; \
      echo "go mod download failed (attempt ${i}/5), retrying..."; \
      sleep $((i * 4)); \
    done; \
    go mod download

COPY . .

RUN CGO_ENABLED=0 go build -o product-catalog .

####################################

FROM alpine AS release

WORKDIR /usr/src/app/

COPY ./products/ ./products/
COPY --from=builder /usr/src/app/product-catalog/ ./

ENV PRODUCT_CATALOG_PORT=8088
ENTRYPOINT [ "./product-catalog" ]
