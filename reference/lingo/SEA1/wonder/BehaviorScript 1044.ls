on exitFrame
  global effectspath
  set the locH of sprite 16 to the locH of sprite 20
  set the locV of sprite 16 to the locV of sprite 20
  updateStage()
  sound playFile 1, effectspath & "floor.aif"
end
