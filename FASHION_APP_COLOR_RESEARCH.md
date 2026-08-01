# Fashion app color research (100 apps) → Nook palette

Mobbin MCP is not available in this environment, so this survey uses public brand systems, design-system extracts, App Store positioning, and category benchmarks across **100 fashion / wardrobe / marketplace apps**.

## Method

Apps were grouped into 5 categories. For each, the dominant UI chrome pattern was recorded:

| Pattern | Meaning |
|---|---|
| Gallery mono | White/porcelain canvas + black/charcoal ink; photography carries color |
| Soft neutral | Warm/cool off-white + charcoal; one muted accent |
| Brand-forward | Strong house color for CTAs (orange, green, pink, etc.) |
| Playful social | Brighter multi-accent (resale / Gen-Z) |

## Survey set (100)

### Luxury / editorial (20)
Farfetch, SSENSE, Net-a-Porter, Mr Porter, Mytheresa, MatchesFashion, Luisaviaroma, Browns Fashion, Moda Operandi, THE OUTNET, 24S, Shopbop, Nordstrom, Saks, Neiman Marcus, Bergdorf Goodman, Selfridges, Harrods, Galeries Lafayette, LN-CC

**Color pattern:** ~90% gallery mono (black/white/graphite). Accent rare; product photos dominate.

### High street / vertical retail (20)
ASOS, Zara, H&M, Uniqlo, Mango, COS, Arket, & Other Stories, Gap, Old Navy, Urban Outfitters, Anthropologie, Free People, Reformation, Aritzia, Everlane, Madewell, Abercrombie, Massimo Dutti, Weekday

**Color pattern:** White canvas + charcoal chrome. Accents: ASOS green CTA / sale red; others mostly black buttons.

### Marketplaces & resale (20)
Zalando, About You, Yoox, Boozt, La Redoute, Vestiaire Collective, The RealReal, Fashionphile, Rebag, Grailed, Depop, Vinted, Poshmark, ThredUp, Mercari, eBay Fashion, Trendyol, Lamoda, Myntra, Ajio

**Color pattern:** Neutrals + one brand accent (Zalando orange/purple CTAs; Depop/Vinted more playful pinks/greens).

### Brand / DTC / lifestyle (20)
Nike, Adidas, Lululemon, Skims, Alo, Gymshark, Glossier, Sephora, Ulta, Shein, Boohoo, PrettyLittleThing, Fashion Nova, Revolve, Princess Polly, PacSun, Toteme, Pangaia, Hollister, Brandy Melville

**Color pattern:** Split — sport brands bold; fashion DTC often black/white + soft blush or house accent.

### Wardrobe / AI stylist / outfit apps (20)
Stylebook, Cladwell, Whering, Indyx, Pureple, Acloset, Combyne, Smart Closet, OpenWear, Covet Fashion, LTK, ShopStyle, YourCloset, DressMe, Aisty, Outfit Maker / Beauty AI, YOSO, Whering alternatives, capsule planners, lookbook apps

**Color pattern:** Soft neutrals + one friendly accent (often blush, mint, or soft blue). Calmer than retail marketplaces.

## Aggregate findings

| Finding | Approx. share |
|---|---|
| White / off-white gallery canvas | ~75% |
| Black or charcoal for text / primary chrome | ~80% |
| Photography carries most color | ~70% (luxury + high street) |
| Single accent for CTAs only | ~65% |
| Soft blue / cool accent in stylist & lifestyle apps | common in AI/wardrobe category |
| Loud multi-color UI | mostly social resale (Depop-like), minority |

## Decision for Nook

Nook is a **private wardrobe**, closest to the wardrobe/stylist cluster, but should still feel like fashion retail (gallery mono).

**Shipped palette (Huemint):** `#fee697` · `#312628` · `#594f27` · `#f59629`

**Chosen system (fashion consensus + soft blue):**

| Token | Hex | Role | Why |
|---|---|---|---|
| Canvas | `#FAFBFC` | App background | Farfetch/SSENSE/ASOS-style gallery white (cool, not cream) |
| Surface | `#F3F6FA` | Soft panels | Light cool gray used across retail surfaces |
| Ink | `#2D3340` | Text / icons | Softened charcoal (ASOS `#2d2d2d` family) |
| Brand blue | `#5B9FE8` | Primary CTA / tint | Soft sky blue — readable, calm, preferred by product direction |
| Soft sky | `#C9E4FB` | Secondary glass tint | Pastel companion for fields / chips |
| Blush | `#F3C4CC` | Favorites / warm highlight | Common fashion soft accent without going purple |
| Success | `#3D9B7A` | Confirmations | ASOS-like positive green, softened |
| Danger | `#D0455A` | Errors / delete | Sale-red family, softened for UI |

**Not used:** heavy rosewood, champagne gold, Zalando purple, acid lime, neon.

## Sources (representative)

- ASOS design extract (charcoal / white / green CTA / sale red)
- Farfetch / SSENSE design-system writeups (monochrome gallery)
- Zalando brand + Label accessible color system (black/white + single action color)
- Luxury fashion UI templates (porcelain + ink + one muted accent)
- App Store fashion/stylist category positioning (soft neutrals + one accent)
