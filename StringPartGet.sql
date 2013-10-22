create function StringPartGet ( 
	@String nvarchar(500),
	@Separator char(1), 
	@LocationId int )
returns nvarchar(499)
as
begin

declare @StringArray table
(
	LocationId int identity(1,1), 
	StringPart nvarchar(256)
)

declare @StringPart nvarchar(256) = ''
set @String = @String + @Separator

declare @StartChar int = 1
declare @EndChar int = len(@String) + 2

while @StartChar < @EndChar 
begin

	set @StringPart = @StringPart + substring(@String, @StartChar, 1)
	
	if substring(@String, @StartChar, 1) = @Separator
	begin
		insert @StringArray values (replace(@StringPart, @Separator,''))
		set @StringPart = ''

		if (select max(LocationId) from @StringArray) = @LocationId
		begin
			goto returnStringPart
		end
	end

	set @StartChar += 1

end

	returnStringPart:
		select @StringPart = 
							case 
								when (isnull(StringPart, '') = '' and LocationId = 1) then 'root' 
								else StringPart 
							end
		from @StringArray 
		where LocationId = @LocationId

		return @StringPart

end
