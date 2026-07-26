on mouseUp
  repeat with i = 1 to 20
    puppetSprite(i, 0)
    sprite(i).visible = 1
  end repeat
  set the keyDownScript to EMPTY
  go("mainmenu")
end
