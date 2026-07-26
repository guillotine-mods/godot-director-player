on exitFrame
  if rollOver(4) then
    set the memberNum of sprite 4 to the number of member "newlp"
    set the memberNum of sprite 5 to the number of member "loa"
    set the memberNum of sprite 6 to the number of member "credi"
    set the memberNum of sprite 7 to the number of member "exi"
  else
    if rollOver(5) then
      set the memberNum of sprite 4 to the number of member "ne"
      set the memberNum of sprite 5 to the number of member "loadlp"
      set the memberNum of sprite 6 to the number of member "credi"
      set the memberNum of sprite 7 to the number of member "exi"
    else
      if rollOver(6) then
        set the memberNum of sprite 4 to the number of member "ne"
        set the memberNum of sprite 5 to the number of member "loa"
        set the memberNum of sprite 6 to the number of member "creditlp"
        set the memberNum of sprite 7 to the number of member "exi"
      else
        if rollOver(7) then
          set the memberNum of sprite 4 to the number of member "ne"
          set the memberNum of sprite 5 to the number of member "loa"
          set the memberNum of sprite 6 to the number of member "credi"
          set the memberNum of sprite 7 to the number of member "exitlp"
        else
          set the memberNum of sprite 4 to the number of member "ne"
          set the memberNum of sprite 5 to the number of member "loa"
          set the memberNum of sprite 6 to the number of member "credi"
          set the memberNum of sprite 7 to the number of member "exi"
        end if
      end if
    end if
  end if
end
