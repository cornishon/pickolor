# Pickolor
A simple color picker for X11 which doesn't block your input

## Demo


https://github.com/user-attachments/assets/1969d548-ed9f-418e-b2e8-c92cb803b417



## Setup

- Install [Odin](https://odin-lang.org/)
- Install `libx11` and `libxi` development headers for you distribution
  - ex `sudo apt install libx11-dev libxi-dev` on Debian based distributions
- Run `odin build . -o:speed` from the project directory
- Run the executable. You can then see the preview window following your cursor, press `space` to pick a color and `escape` to exit. The color is copied to you clipboard.
