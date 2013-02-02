## App::DuckDuckGo::UI
----------------------

This is an interactive Curses-based user interface for DuckDuckGo.

#### Screenshots:
![screenshot 1](http://i.imgur.com/KKtIIVk.jpg)
![screenshot 2](http://i.imgur.com/kIe77cf.jpg)
---------------

#### Known bugs:
* Clicking the last result after scrolling down any amount gets the wrong URL
* UI glitches while autocompleting
* Selection background on results does not extend to the far right of the screen
* Certain queries at certain times simply do not return results. The `fill_deep` method is never called.
