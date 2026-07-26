on mouseUp
  global objectxx, objectyy
  set the locH of sprite the clickOn to objectxx
  set the locV of sprite the clickOn to objectyy
  updateStage()
end

on mouseDown
  global objectxx, objectyy
  objectxx = the locH of sprite the clickOn
  objectyy = the locV of sprite the clickOn
end
