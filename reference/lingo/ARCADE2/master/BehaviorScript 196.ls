on exitFrame
  set the keyDownScript to "zigiscript"
  set the visible of sprite 5 to 0
  set the visible of sprite 6 to 0
  repeat with i = 8 to 30
    set the visible of sprite i to 1
  end repeat
  repeat with i = 23 to 30
    set the visible of sprite i to 0
  end repeat
  puppetSprite(40, 1)
end
