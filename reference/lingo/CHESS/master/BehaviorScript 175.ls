on enterFrame
  global soundspath, effectspath
  repeat with i = 10 to 62
    puppetSprite(i, 0)
    sprite(i).visible = 0
  end repeat
  set the volume of sound 2 to 255
  sound playFile 2, effectspath & "drama.aif"
end
