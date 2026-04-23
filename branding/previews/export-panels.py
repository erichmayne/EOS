import asyncio
from playwright.async_api import async_playwright

URL = "http://localhost:8787/thumbnails/previews/appstore-previews-v2.html"
OUT = "/Users/emayne/morning-would/branding/thumbnails/previews/exports"
W, H = 1290, 2796

PANELS = [
    "01-set-your-goal",
    "02-compete-win-money",
    "03-runmatch-branding",
    "04-challenge-friends",
    "05-bet-on-better-you",
]

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": W, "height": H})
        await page.goto(URL, wait_until="networkidle")
        await page.wait_for_timeout(1500)

        for name in PANELS:
            await page.evaluate(f"""() => {{
                const strip = document.getElementById('strip');
                const overlay = document.getElementById('overlay');
                document.querySelectorAll('.panel.isolated').forEach(p => {{
                    p.classList.remove('isolated');
                    if (p.parentNode === document.body) strip.appendChild(p);
                }});
                overlay.classList.remove('active');
                const target = document.querySelector('[data-name="{name}"]');
                document.body.appendChild(target);
                target.classList.add('isolated');
                overlay.classList.add('active');
            }}""")
            await page.wait_for_timeout(500)

            path = f"{OUT}/{name}.png"
            await page.screenshot(path=path, clip={"x": 0, "y": 0, "width": W, "height": H})
            print(f"  saved {name}.png")

        await browser.close()
        print(f"\nDone — 5 images in {OUT}")

asyncio.run(main())
