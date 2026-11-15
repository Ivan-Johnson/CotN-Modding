* Have LLM identify fill in major gaps in the docs. e.g. the docs probably
  assume that the reader already knows stuff such as:

  * Basic character mechanics: equipment slots, how glass gear works, etc
  * How all the different characters work (cadence vs melody vs aria ...)
  * Boss mechanics (esp story mode bosses?)
  * Enemy mechanics (e.g. most enemies are cardinal & every-other beat)

* Make docs more ergonomic. (I'm not really sure what that would look like...
  Partly done: `nix build .#docs` leaves the Markdown at
  `result/docs/markdown/`, which agents search with `grep`/`view`.
