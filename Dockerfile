FROM swift:6.3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git pkg-config libsqlite3-dev
WORKDIR /workspace
COPY . .
RUN swift --version
RUN swift build -Xcc -fimplicit-modules
RUN swift test
RUN swift test --trait wallet
CMD ["swift", "test"]