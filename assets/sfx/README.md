# Authored SFX drop-in

Everything in this game is synthesised from oscillators at runtime (`audio.gd`).
That is coherent but it is the least finished sensory layer, and a licensed pack
is the single biggest step up available.

**To swap one in:** drop a file named after the sound into this folder. It wins
over the synthesised version automatically — no code change.

    assets/sfx/eliminate.wav      replaces the generated "eliminate"

Recognised extensions: `.wav`, `.ogg`, `.mp3`.

Names currently synthesised:

    absorb  absorb_big  launch  eliminate  hit  charge_ready
    ui_tap  size_up  alarm  reward  win  lose  hum

The boot log prints `sfx: N authored, M synthesised`, so a partially installed
pack is visible rather than silently ignored.

**Licensing:** only ship audio you have the rights to. The spec forbids
copyrighted assets (§15.8). Nothing in this folder is checked in.
