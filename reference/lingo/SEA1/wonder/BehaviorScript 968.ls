on enterFrame
  global maa
  puppetSprite(16, 1)
  set the visible of sprite 20 to 0
  set the locH of sprite 16 to the locH of sprite 20
  set the locV of sprite 16 to the locV of sprite 20
  set the memberNum of sprite 16 to the number of member (maa & "lop") of castLib 1
  set the memberNum of sprite 20 to the number of member (maa & "lop") of castLib 1
  updateStage()
end
