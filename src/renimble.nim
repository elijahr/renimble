# renimble - Definitive automated dependency updater for Nim projects (.nimble & nimble.lock)

const projectVersion* = "0.0.1"

const greetingMsg* = "hello from renimble"

proc hello*(): string =
  ## Returns standard project greeting string.
  greetingMsg

proc add*(a, b: int): int =
  ## Adds two integers.
  a + b
