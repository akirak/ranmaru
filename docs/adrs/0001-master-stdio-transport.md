# ADR 0001: Support master communication over stdio

Status: Draft
Date: 2025-09-27

## Context

Ranmaru currently communicates with the master over a Unix socket, configured
via `--master` or `RANMARU_MASTER_SOCKET`. However, most language servers only
support communication over stdio. UNIX sockets are not common. The ecosystem of
LSP has also evolved around stdio.

## Decision

Add support for communicating with the master over stdio (stdin/stdout) while
retaining the existing socket-based transport. When stdio is used for
communication, the master server must be specified in the command line, so it is
started and exited by ranmaru. This is called the managed mode and have a
different process semantics from using a server running independently.

## Specification

### Stdio communication

- Enable stdio transport with `--stdio-master -- COMMAND [ARGS]`.
- Start the master process as a direct child of ranmaru using the provided
  command line.
- Wire the child's stdin/stdout to ranmaru's LSP transport stream.
- Treat the stdio stream as raw JSON-RPC; no extra framing, logging, or
  diagnostic output is allowed on stdout.
- Route the child's stderr to ranmaru's stderr so diagnostics remain visible
  without corrupting the JSON-RPC stream.
- Reject configurations that try to use both `--master` and `--stdio-master`
  simultaneously.

### Master process lifecycle

- Spawn the master process before accepting client connections so it is ready
  to serve the first request.
- Do not forward client `shutdown` requests or `exit` notifications from clients
  to the master; ranmaru keeps the master alive across client reconnects.
- If the master process exits or its stdout closes, treat it as fatal:
  close client connections and exit ranmaru with a non-zero status.
- When ranmaru is asked to terminate (signal or CLI exit), send a shutdown
  request to the master server and wait for an exit notification, as specified
  the LSP specification. This behavior is specific to the master mode.

## Consequences

- Ranmaru will need a new code path to spawn the master process and wire its
  stdio to the LSP transport.
- Stdio will be reserved for the master transport, so other uses (logging,
  client transport) must avoid colliding with it.
- Socket transport remains available for deployments that already rely on it.
- Tests should cover both transport types to prevent regressions.


## Alternatives Considered

- Keep only Unix socket transport and rely on wrappers to adapt stdio (rejected:
  adds operational complexity for common LSP setups).
- Add TCP transport (rejected: more configuration surface and still uncommon in
  LSP environments compared to stdio).


## Related ADRs

None.
