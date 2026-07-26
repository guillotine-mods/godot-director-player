on exitFrame
  global soundspath
  set the keyDownScript to EMPTY
  set the keyDownScript to "fromnow"
  puppetSprite(7, 0)
  puppetSprite(9, 0)
  sound playFile 1, soundspath & "jump.aif"
end
