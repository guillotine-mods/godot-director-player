on exitFrame
  global soundspath
  set the keyDownScript to "hitback"
  puppetSprite(7, 1)
  puppetSprite(9, 0)
  sound playFile 1, soundspath & "birdi.aif"
end
