on exitFrame
  global soundspath
  repeat with i = 8 to 15
    puppetSprite(i, 0)
  end repeat
  sound playFile 1, soundspath & "artmore.aif"
end
