// Fills itch.io's project form (new or edit) for Fizz Fling. Run with:
//   node tools/itch/cdp.mjs evalfile tools/itch/fill_page.js
(() => {
  const set = (n, v) => { const e = document.querySelector(`[name="${n}"]`); if (!e) return; e.value = v;
    e.dispatchEvent(new Event("input", { bubbles: true })); e.dispatchEvent(new Event("change", { bubbles: true })); };
  set("game[title]", "Fizz Fling");
  set("game[slug]", "fizz-fling");
  set("game[short_text]", "Shake your phone. Tilt to aim. POP! How far can the cap fly?");
  for (const [n, v] of [["game[type]", "html"], ["game[release_status]", "prototype"], ["game[genre]", "sports"]])
    document.querySelector(`select[name="${n}"]`).selectize.setValue(v);
  const html = "<p><strong>Shake your phone as hard as you can</strong> to build up the fizz in a soda bottle, then <strong>tilt it to aim</strong> &mdash; and <strong>POP!</strong> The cap blasts down the park field and the soda sprays out after it.</p>"
    + "<p>Your score is how far the cap flies <strong>plus</strong> how far the spray reaches.</p>"
    + "<ul><li><strong>Solo:</strong> beat your own best distance.</li><li><strong>Party:</strong> pass one phone round 2&ndash;6 friends, 1 or 3 rounds, best throw wins.</li><li>The wind changes every turn &mdash; adjust your aim. About 40&deg; flies furthest.</li></ul>"
    + "<h2>Play it on a phone</h2><p>Fizz Fling uses your phone&rsquo;s motion sensors. <strong>On iPhone, tap PLAY FULL SCREEN</strong> and allow motion access when asked (iPhones don&rsquo;t share motion with a game inside another page).</p>"
    + "<p>No motion sensor? Rub the screen fast to shake and drag to aim &mdash; or on a computer, mash Left/Right and use the arrow keys.</p>"
    + "<h2>Credits</h2><p>Made with Godot. Every 3D model built in Blender. Sounds CC0 from Freesound and Kenney. Font: Lilita One (OFL).</p>";
  const ta = document.querySelector('textarea[name="game[description]"]');
  jQuery(ta).redactor("code.set", html); jQuery(ta).redactor("code.sync");
  const t = document.querySelector('input[name="game[tags]"]');
  for (const x of ["3d", "casual", "funny", "local-multiplayer", "low-poly", "party-game", "physics", "sports", "motion-control"]) {
    t.selectize.addOption({ value: x, text: x }); t.selectize.addItem(x); }
  const yes = document.querySelector('input[name="ai_disclosure[ai_generated]"][value=yes]'); if (!yes.checked) yes.click();
  // honest disclosure: the code, the model-building scripts and the text were written by an AI
  // assistant; the sounds are human-made CC0 recordings
  for (const n of ["ai_graphics", "ai_text", "ai_code"]) { const e = document.querySelector(`input[name="ai_disclosure[${n}]"]`); if (e && !e.checked) e.click(); }
  const a = document.querySelector('input[name="ai_disclosure[ai_audio]"]'); if (a && a.checked) a.click();
  return { title: document.querySelector('[name="game[title]"]').value, type: document.querySelector('select[name="game[type]"]').value,
    desc: ta.value.length, tags: t.value };
})()
