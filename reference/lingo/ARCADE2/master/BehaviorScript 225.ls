on exitFrame
  global effectspath
  repeat with i = 1 to 50
    sprite(i).visible = 1
  end repeat
  sound playFile 2, effectspath & "action.aif"
  set the keyDownScript to EMPTY
  set the memberNum of sprite 40 to the number of member "zigi4"
  updateStage()
end
