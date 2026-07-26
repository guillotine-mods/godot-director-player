on mouseUp
  global afganicnt, effectspath
  x = the memberNum of sprite 10
  if member(x, "book").name = "afgan1" then
    sound playFile 1, effectspath & "clik2.aif"
  else
    x = value(char 6 to 7 of the name of member x of castLib "book")
    if x > 0 then
      sound playFile 1, effectspath & "clik3.aif"
      set the memberNum of sprite 11 to the number of member ("afgan" & x - 1) of castLib "book"
      set the memberNum of sprite 10 to the number of member ("afgan" & x - 2) of castLib "book"
    else
      set the memberNum of sprite 10 to the number of member "afganempty" of castLib "book"
      sound playFile 1, effectspath & "clik2.aif"
    end if
  end if
end
