---
name: medusa
description: Drive the user's running Medusa browser from the terminal with `medusa exec` (Python and pydoll over the Chrome DevTools Protocol). Use when a task needs a real browser with the user's logins, to read the page the user is looking at, open pages, click, type, take screenshots or run JavaScript.
---

# Driving Medusa with `medusa exec`

`medusa exec` runs Python against the Medusa the user has open, with top-level `await`. The value of the last
expression is printed: strings as they are, anything else as its repr, or JSON with `--json`. Every run is a new
process, so carry state between runs in a URL or a file, not a variable.

```sh
medusa exec 'await tab.title()'
medusa exec --json '[await t.current_url() for t in tabs]'
medusa exec -f script.py
```

In scope:

- `tab`: the web page the user is looking at when the run starts, even with Medusa's window covered. When they're on
  New Tab or another Medusa view, any use of `tab` raises `NoPageTab` (and `bool(tab)` is False): open a page with
  `new_tab` instead.
- `tabs`: every web page tab when the run starts, the user's own included, plus the ones `new_tab` opens.
- `new_tab(url, background=True)`: opens a tab in the sidebar, waits for the page to load and returns it.
  `background=False` switches the user to it.
- `js(expression, tab=None)`: evaluates JavaScript and returns its value. Pass `tab=t` for your own tab; without
  it, `js` uses the user's tab, else the last tab you opened, else raises `NoPageTab`.
- `browser` (pydoll `Chrome`), `By`, `Key`, `asyncio` and the rest of `pydoll`'s exports.

Exit status: 0 done, 1 your code raised or timed out (`--timeout`, default 300 s), 2 Medusa can't be reached or
stopped the connection.
On exit 2, tell the user to open Medusa and turn on Settings › "Let the medusa command control Medusa".

## Etiquette

This is the user's own browser, signed in to their accounts.

- Do your work in a tab you open with `new_tab`. Read the user's `tab`, but don't navigate it unless they ask.
- Close only the tabs you opened (`await t.close()`), and only when you're done with them.
- Delete the scratch scripts you wrote; keep the files the user asked for (screenshots, exports).
- Ask before anything with consequences: submitting forms, sending messages, posting, buying, deleting,
  changing settings or accepting dialogs.
- Don't read or export cookies, passwords or storage unless the user asks for exactly that.

## Recipes

Read the page the user is on (raises `NoPageTab` on New Tab):

```sh
medusa exec 'await tab.current_url(), await tab.title()'
medusa exec 'await js("document.body.innerText.slice(0, 5000)")'
```

Open a page and work there. Every run starts over, so find your tab again by URL:

```sh
medusa exec 't = await new_tab("https://example.com"); await js("document.links[0].href", tab=t)'
medusa exec 't = [t for t in tabs if "example.com" in await t.current_url()][0]; await t.page_source()'
```

Longer work goes in a file. Close your tab, then put the data on the last line so it's printed:

```python
t = await new_tab("https://news.ycombinator.com")
rows = await js("[...document.querySelectorAll('.titleline > a')].slice(0, 3).map(a => [a.innerText, a.href])", tab=t)
await t.take_screenshot("/tmp/hn.png")
await t.close()
rows
```

```sh
medusa exec --json -f /tmp/hn.py && rm /tmp/hn.py
```

Find, click and type:

```python
t = await new_tab("https://example.com/search")
box = await t.query('input[name="q"]', timeout=10)
await box.type_text("medusa browser\r")
await t.wait_for_url("**?q=*", timeout=15)
results = await t.query("h3", find_all=True)
[await r.text() for r in results[:5]]
```

`query` takes CSS or XPath; `find(tag_name=..., id=..., class_name=..., name=..., text=..., **attributes)` builds
the selector for you. Both wait up to `timeout` seconds for the element. When it isn't there they raise
`ElementNotFound` (with `timeout=0`, the default) or `WaitElementTimeout` (with a timeout), or return `None` with
`raise_exc=False`. For a click that loads a new page:

```python
async with t.expect_navigation():
    await (await t.find(tag_name="a", text="Next")).click()
```

Wait for things:

```python
await (await t.query("#results", timeout=10)).wait_until(is_visible=True, timeout=10)
await t.wait_for_script("document.readyState === 'complete'", timeout=10)
await t.wait_for_network_idle(timeout=15)
```

Screenshots and PDFs go to a file:

```sh
medusa exec 'await tab.take_screenshot("/tmp/page.png"); "/tmp/page.png"'
medusa exec 'await tab.take_screenshot("/tmp/full.png", beyond_viewport=True)'
medusa exec 'el = await tab.query("main"); await el.take_screenshot("/tmp/main.png")'
medusa exec 'await tab.print_to_pdf("/tmp/page.pdf")'
```

Run JavaScript: `js()` returns plain values (awaiting promises) and raises on a JavaScript error.

```sh
medusa exec --json 'await js("[...document.links].slice(0, 20).map(a => ({text: a.innerText, href: a.href}))")'
```

The full pydoll 3.0 API is in `references/pydoll.md`.

## Gotchas

- Tab and element methods are coroutines: `await tab.title()`, `await tab.current_url()`, `await el.text()`.
  `el.get_attribute("href")` is a plain call and `el.tag_name` a plain property, both read when the element was found.
- `medusa exec` refuses `browser.stop()` and `Browser.close`. It never quits Medusa.
- It reaches web pages only (http, https, `about:blank`, `data:`, `blob:`), not `file://`, `chrome://`, extension
  pages or Medusa's own views. Medusa also refuses DevTools calls that read cookies, storage or saved data, change
  browser settings or permissions, intercept requests or touch local files; those fail with
  `medusa: <Method> isn't allowed for the medusa command`. Network events come without cookie and authorization headers.
- Background tabs are hidden, so pages there may throttle timers and animations. Screenshots still work.
- An `await` inside a generator expression makes it async, so `next(... await ...)` fails. Use a list comprehension.
- Type with `type_text` (real key events) when a page listens for keys; `insert_text` is faster for plain fields.
- To press Enter in a field, end the typed text with `"\r"`. `keyboard.press(Key.ENTER)` sends no character, so it
  doesn't submit forms; use it for key handlers only.
