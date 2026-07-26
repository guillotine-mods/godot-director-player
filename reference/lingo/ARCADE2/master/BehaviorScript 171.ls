on exitFrame
  global effectspath
  if not soundBusy(2) then
    sound playFile 2, effectspath & "action.aif"
  end if
  put 4 into field "score"
  set the memberNum of sprite 40 to the number of member "zigi4"
  updateStage()
end
