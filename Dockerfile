FROM swift:6.3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git pkg-config libsqlite3-dev
WORKDIR /workspace
COPY . .
ARG TRAITS=
RUN swift test ${TRAITS:+--traits $TRAITS}
