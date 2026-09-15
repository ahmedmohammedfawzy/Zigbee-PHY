# CSS PHY HTML presentation

Open `index.html` in a browser. Use the left and right arrow keys to move between slides.

Keyboard controls:

- `O`: slide overview
- `N`: speaker notes
- `F`: full screen
- `Home` / `End`: first / last slide

The file is intentionally self-contained and uses no external libraries or web fonts. Edit slide copy directly in `index.html`.

## Team edits before presenting

1. Replace the team, supervisor, and date placeholders on slide 1.
2. Add measured area, timing, power, and FPGA utilization values.
3. Replace the screenshot frames on slides 14 and 15. The suggested filenames are shown inside each frame. To use an image, replace the placeholder `<div class="screenshot">...</div>` with `<img class="screenshot-img" src="assets/your-file.png" alt="...">` and add `.screenshot-img { width: 100%; height: 520px; object-fit: contain; }` to the CSS.
4. Regenerate the missing golden CSV files if you want to claim all four full-chain cases pass.

## PDF export

Use the browser print command and choose landscape orientation with background graphics enabled. Each slide has its own 16:9 print page.
