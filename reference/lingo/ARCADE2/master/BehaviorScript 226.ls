on exitFrame
  global effectspath
  sound playFile 2, effectspath & "action.aif"
  put value(the text of field "score") + 1 into field "score"
  set the memberNum of sprite 40 to the number of member ("zigi" & value(the text of field "score"))
end
