on exitFrame
  global foe, effectspath
  soundspath("games")
  put 0 into field "hatscore"
  put 0 into field "hezscore"
  if not soundBusy(2) then
    set the volume of sound 2 to 50
    sound playFile 2, effectspath & "arcade.aif"
  end if
end
