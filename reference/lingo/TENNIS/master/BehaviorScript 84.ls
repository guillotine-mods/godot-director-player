on exitFrame
  global serve, soundspath
  puppetSprite(7, 0)
  put value(the text of field "hatscore") + 1 into field "hatscore"
  serve = serve + 1
  if serve > 10 then
    serve = 1
  end if
  updateStage()
  if value(the text of field "hatscore") >= 12 then
    set the keyDownScript to "fromnow"
    go("hatwin")
  else
    zzz = random(3)
    if zzz = 1 then
      sound playFile 1, soundspath & "hezmiss" & random(5) & ".aif"
      sprite(13).visible = 0
      sprite(9).visible = 0
      set the keyDownScript to "fromnow"
      play frame "hatspk2"
      sprite(13).visible = 1
      sprite(9).visible = 1
    else
      if zzz = 2 then
        sound playFile 1, soundspath & "hatscor" & random(5) & ".aif"
        sprite(13).visible = 0
        sprite(9).visible = 0
        set the keyDownScript to "fromnow"
        play frame "hatspk1"
        sprite(13).visible = 1
        sprite(9).visible = 1
      end if
    end if
    if serve > 5 then
      go("hezserve")
    else
      go("hatserve")
    end if
  end if
end
