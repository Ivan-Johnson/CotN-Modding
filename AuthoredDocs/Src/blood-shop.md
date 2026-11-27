# Blood shop

For players. The secret shop that sells its wares for health, and its
shopkeeper. Applies to Cadence in a single-zone run of zone one. Finding the
shop (its cracked wall, the travel rune, and which levels have it):
[secret-shops.md](./secret-shops.md).

* The shop is a small room with the blood shopkeeper (`Shopkeeper2`) at the
  back and three wares in a row two tiles in front of him. The left ware is
  a gold weapon, such as a golden harp, staff or trident.

## Buying

* Each ware is priced in health, not gold: walk onto it and the price comes
  out of your current health, not your maximum. You step onto its tile
  holding the item. A price is a few health, such as 3 (one and a half
  hearts) for the gold weapon and 2 for food or a torch.
* Nothing stops a purchase you cannot afford. With no more health than the
  price, you still get the item, and the price kills you, as "Blood Debt".

## The shopkeeper

* Until he is provoked, your weapon cannot hurt him: attacking him does
  nothing, and he never attacks you.
* A bomb that hurts him provokes him. He has 8 health and a bomb takes 4.
* Provoked, he hits for 20 every second beat while beside you. Your weapon
  now hurts him: a dagger takes 1 per hit. His wares keep their price while
  he lives.
* Killed, he drops a Blood Drum (`BloodDrum`,
  [action-items.md](./action-items.md)) where he dies, and the wares left
  are free.
