create function EpochToDate ( @UnixTimestamp bigint )
returns datetime
as
begin

return dateadd
		(
			ms, 
			@UnixTimestamp%(3600*24*1000), 
			dateadd(day, @UnixTimestamp/(3600*24*1000), '1970-01-01 00:00:00.0')
		)

end
