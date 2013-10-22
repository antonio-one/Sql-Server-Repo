create function SecondsToTime (@Seconds int)
returns char(8)
as
begin

	return convert(char(8),dateadd(second,@Seconds,0),108)

end
