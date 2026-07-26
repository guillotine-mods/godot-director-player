on exitFrame
  put "0" into field "score"
  repeat with i = 100 to 109
    sprite(i).visible = 1
  end repeat
  set the keyDownScript to EMPTY
  sprite(94).visible = 1
  sprite(95).visible = 1
  sprite(96).visible = 1
  sprite(106).visible = 1
  set the volume of sound 2 to 75
  soundspath("games")
end
