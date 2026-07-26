on mouseUp
  global afganicnt, effectspath
  x = the memberNum of sprite 11
  if member(x, "book").name contains "empty" then
    sound playFile 1, effectspath & "clik2.aif"
  else
    x = value(char 6 to 7 of the name of member x of castLib "book")
    if afganicnt > x then
      sound playFile 1, effectspath & "clik3.aif"
      set the memberNum of sprite 10 to the number of member ("afgan" & x + 1) of castLib "book"
      if afganicnt > (x + 1) then
        set the memberNum of sprite 11 to the number of member ("afgan" & x + 2) of castLib "book"
      else
        set the memberNum of sprite 11 to the number of member "afganempty" of castLib "book"
      end if
    else
      sound playFile 1, effectspath & "clik2.aif"
    end if
  end if
end
