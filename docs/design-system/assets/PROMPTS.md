# 图片生成提示词

每条提示词生成一张图，文件名写在标题里，生成后放到对应文件夹。提示词用英文，图像模型对英文的理解更稳定。

所有图片都要遵守的通用要求，已写进每条提示词末尾：

> Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.

---

## 一、App 图标（先出方向，选定后再出变体）

### app-icon/concept-1.png · concept-2.png · concept-3.png

一次生成三个不同方向，选一个再做下面四张。

```
Design three different app icon concepts for "JamReader", a calm, native-feeling iPhone/iPad comic reader. Output each as a separate 1024x1024 square PNG, full-bleed, opaque, no rounded corners (iOS adds the mask), no text or letters.

Brand colors: jam #9B1E56 (deep red-purple, like raspberry jam), deep jam #5C1233, honey gold #B97F00 as a small accent only, warm cream #FFF4EA.

Directions:
1. A single bold comic speech bubble whose lower edge melts into one glossy jam drip; cream bubble on a deep jam background.
2. An open book seen from the front whose two pages are simple comic panel grids; one panel filled with jam color like a spoonful of jam; on a cream background.
3. A minimal jam jar silhouette whose label is a tiny 2x2 comic panel grid; deep jam jar on a cream background, one small honey-gold highlight.

Style: flat, geometric, Apple-like simplicity, one or two shapes, generous margins (keep the motif inside the central 80%), soft subtle depth at most, must stay recognizable at 29pt. No gradients piled on top of each other, no photorealism, no busy detail.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### app-icon/icon-light.png

把选中的 concept 作为参考图一起发给模型。

```
Using the attached concept as the exact design reference, produce the final iOS app icon: 1024x1024 PNG, full-bleed, fully opaque, no rounded corners, no text. Keep the motif inside the central 80%. Colors: jam #9B1E56, deep jam #5C1233, cream #FFF4EA, honey gold #B97F00 only as a tiny accent. Clean vector-like edges, flat with at most one soft highlight. Must read clearly at 29pt.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### app-icon/icon-dark.png

```
Using the attached light icon as the exact design reference, produce the iOS dark-appearance variant: 1024x1024 PNG with a fully transparent background (iOS supplies the dark backdrop). Same motif, same position and size. Recolor for a dark backdrop: main shape raspberry jam #C23A76, highlights soft jam pink #E886B2, cream details #FFF4EA, honey #FFD60A only as a tiny accent. No text, no rounded corners.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### app-icon/icon-tinted.png

```
Using the attached light icon as the exact design reference, produce the iOS tinted-appearance variant: 1024x1024 PNG, fully transparent background, the motif in grayscale only (white for the most prominent shape, mid grays for secondary shapes), same position and size. iOS will tint it with the user's chosen color. No text, no rounded corners.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### app-icon/icon-foreground.png

```
Using the attached light icon as the exact design reference, output only the foreground motif as a separate layer: 1024x1024 PNG, fully transparent background, same colors, same position and size as in the light icon, nothing else in the image. This layer will be used to build a layered Liquid Glass icon in Icon Composer.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

---

## 二、示意封面（9 张，600×900，2:3 竖版）

目的：检验封面网格上的角标、底部进度条、书名在真实画面上的可读性，所以要有亮、暗、复杂三类，每类 3 张。书名直接画在封面上，像真实出版物一样。

### covers/cover-01.png · 亮 · 白底为主

```
A comic book cover, 600x900 PNG portrait (2:3). Slice-of-life story: a small figure riding a bicycle along a quiet seaside road, lots of white sky and white negative space, soft pastel blue and pale green accents, delicate ink lines. Title lettering at the top in clean black type: "Summer Slope" with a smaller Japanese subtitle "夏の坂道". Volume number "1" small in a corner. Very bright overall, mostly white, especially the top-right corner and the bottom edge.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-02.png · 亮 · 高饱和黄

```
A comic book cover, 600x900 PNG portrait (2:3). Comedy story: a cheerful cook juggling three oversized dumplings in a tiny kitchen, bold flat colors dominated by saturated lemon yellow, thick black outlines, pop-art halftone dots in the background. Title in big chunky rounded letters across the top: "饺子大作战" with smaller English "Dumpling Panic". Volume number "3". Bright and loud, the top-right corner should be yellow.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-03.png · 亮 · 浅蓝天空

```
A comic book cover, 600x900 PNG portrait (2:3). Sports story: a volleyball player mid-jump seen from below against a huge pale sky-blue sky with a few white clouds, sunlight flare, dynamic speed lines. Title in italic bold white letters with a thin navy outline near the bottom: "Spike Season". Volume number "7". Light and airy, bottom area mostly pale blue.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-04.png · 暗 · 夜色侦探

```
A comic book cover, 600x900 PNG portrait (2:3). Noir mystery: a detective in a long coat under a single streetlamp in a foggy harbor at night, deep navy and near-black tones, wet cobblestones reflecting faint light, heavy shadows. Title in thin elegant off-white serif letters at the top: "雾港侦探" with small English "Harbor Fog". Volume number "3". Very dark overall, especially the bottom third.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-05.png · 暗 · 黑底暗红

```
A comic book cover, 600x900 PNG portrait (2:3). Quiet horror story: an empty old school corridor at night, one classroom door slightly open with dim red light spilling out, near-black background with deep crimson and dark wine red accents, rough ink textures. Title in distressed pale gray letters at the top: "Room 13". Volume number "1". Very dark, with red tones close to a deep raspberry red.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-06.png · 暗 · 太空

```
A comic book cover, 600x900 PNG portrait (2:3). Space science fiction: a small lone spacecraft drifting past a giant dark planet with a thin glowing ring, black starfield, cold teal and violet rim light. Title in wide spaced-out white sans-serif letters at the bottom: "星屑通信" with small English "Stardust Letters". Volume number "2". Mostly black.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-07.png · 复杂 · 黑白网点

```
A comic book cover, 600x900 PNG portrait (2:3). Fantasy adventure in black and white ink only with heavy screentone: a young traveler standing on a cliff over a sprawling walled city full of towers, bridges and banners, dense crosshatching, many small details everywhere including the corners. Title in a bold hand-lettered black banner across the middle: "The Lost Map" with Chinese "失落的地图". Volume number "5". Busy, high-contrast, no color at all.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-08.png · 复杂 · 多彩人群

```
A comic book cover, 600x900 PNG portrait (2:3). Festival story: a crowded night market packed with lanterns, food stalls, signs and dozens of small characters, many saturated colors (orange, teal, magenta, green, yellow), lots of detail edge to edge. Title in a white rounded badge near the top: "山城物语" with small English "Hill Town Tales". Volume number "上". Visually noisy everywhere, including the top-right corner and the bottom edge.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### covers/cover-09.png · 复杂 · 机械线稿

```
A comic book cover, 600x900 PNG portrait (2:3). Mecha / engineering story: a large robot under construction in a hangar, drawn like a technical blueprint mixed with color, many fine lines, measurement marks, grid lines and small labels made of meaningless glyphs, steel gray with bright safety-orange accents. Title in condensed stencil letters at the bottom: "IRON DAYS" with a large "#1". Dense line work across the whole image.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

---

## 三、示意漫画页

目的：检验阅读器顶栏的书名与渐变遮罩、浮动按钮、显示面板在不同画面上的可读性。对白气泡里不要写真实文字，用波浪线代替。

### pages/page-01.png · 白为主

```
A single black-and-white comic page, 1200x1800 PNG portrait. Five panels with thin white gutters on a white page. Gentle everyday scene: two friends talking at a bus stop, light line art, lots of white background, three speech bubbles near the top of the page whose text is replaced by simple wavy scribble lines (no real letters). The top 15% of the page should be mostly white with a bubble near the top-left.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### pages/page-02.png · 黑为主

```
A single black-and-white comic page, 1200x1800 PNG portrait. Four panels, most of them filled with solid black: a night chase through narrow alleys, figures shown as silhouettes with white rim light, rain streaks, one small white speech bubble with wavy scribble lines instead of text. The top 15% of the page should be mostly black.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### pages/page-03.png · 网点密集

```
A single black-and-white comic page, 1200x1800 PNG portrait. Six panels densely packed with screentone gradients, crosshatching, speed lines and sound-effect shapes (abstract, not real letters): a sword duel on a rooftop in strong wind. Detail everywhere including the page edges and corners, mid-gray overall tone. Four speech bubbles with wavy scribble lines instead of text.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```

### pages/strip-01.png · 竖向条漫（彩色）

```
A vertical-scroll color webcomic strip, 800x4000 PNG (very tall). Panels stacked vertically with generous white space between them, full-width panels of varying height: a short story of a cat delivering a letter across rooftops at sunset, warm oranges fading to purple dusk, then a dark night panel near the bottom. Speech bubbles use wavy scribble lines instead of text. The top 400px should be bright, the middle varied, the last 800px dark.

Original artwork only. Do not imitate any existing comic, manga, character, logo, publisher mark or the style of any named artist. No watermark, no signature, no UI elements, no device frame.
```
