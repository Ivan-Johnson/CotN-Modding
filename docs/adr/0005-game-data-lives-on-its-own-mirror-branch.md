# Game data lives on its own branch of the docs mirror

The scraped game data is published to a `game-data` branch of the private
`Ivan-Johnson/CotN-docs` mirror, not to the `mainline` branch the flake pins and
not to a new repo. It is the game's own data (`necrodancer.xml` and so on), so
it may be proprietary. Nobody has checked whether publishing it is allowed.
Keeping it on a branch of its own means either it or the docs can later be made
public without the other, while still sharing one repo and one push mechanism.

## Consequences

* A branch is not a licensing guarantee. The branch's `README.md`, written on
  every push from `DocDownloader/game-data-README.md`, says the risk is
  unchecked.
* The flake never sees the game data, because it pins `mainline`.
* `crawl-and-push.bash` and `push-game-data.bash` share `push-to-mirror.bash`,
  which makes a directory the whole contents of a branch.
* Like the crawl push, `push-game-data.bash` is a real Git push and is never a
  validation step.
