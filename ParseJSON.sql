CREATE FUNCTION [dbo].[ParseJSON]( @JSON NVARCHAR(MAX))
RETURNS @hierarchy table
(
  element_id int IDENTITY(1, 1) NOT NULL,	/* internal surrogate primary key gives the order of parsing and the list order */
  parent_id int,							/* if the element has a parent then it is in this column. The document is the ultimate parent, so you can get the structure from recursing from the document */
  object_id int,							/* each list or object has an object id. This ties all elements to a parent. Lists are treated as objects here */
  name nvarchar(2000),						/* the name of the object */
  stringvalue nvarchar(4000) NOT NULL,		/*the string representation of the value of the element. */
  valuetype nvarchar(100) /* NOT */ null	/* the declared type of the value represented as a string in stringvalue*/
											/* changed to allow nulls 2013/08/23 */
)
 
AS
 
BEGIN
   DECLARE
     @firstobject int, --the index of the first open bracket found in the JSON string
     @opendelimiter int,--the index of the next open bracket found in the JSON string
     @nextopendelimiter int,--the index of subsequent open bracket found in the JSON string
     @nextclosedelimiter int,--the index of subsequent close bracket found in the JSON string
     @type nvarchar(10),--whether it denotes an object or an array
     @nextclosedelimiterChar CHAR(1),--either a '}' or a ']'
     @contents nvarchar(MAX), --the unparsed contents of the bracketed expression
     @start int, --index of the start of the token that you are parsing
     @end int,--index of the end of the token that you are parsing
     @param int,--the parameter at the end of the next Object/Array token
     @endofname int,--the index of the start of the parameter at end of Object/Array token
     @token nvarchar(4000),--either a string or object
     @value nvarchar(MAX), -- the value as a string
     @name nvarchar(200), --the name as a string
     @parent_id int,--the next parent ID to allocate
     @lenjson int,--the current length of the JSON String
     @characters NCHAR(62),--used to convert hex to decimal
     @result BIGINT,--the value of the hex symbol being parsed
     @index SMALLINT,--used for parsing the hex value
     @escape int --the index of the next escape character
 
   /* in this temporary table we keep all strings, even the names of the elements, since they are 'escaped'
    * in a different way, and may contain, unescaped, brackets denoting objects or lists. These are replaced in
    * the JSON string by tokens representing the string
    */
   DECLARE @strings table
   (
     string_id int IDENTITY(1, 1),
     stringvalue nvarchar(MAX)
   )
 
   /* initialise the characters to convert hex to ascii */
   SELECT
     @characters = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
     @parent_id = 0;
 
   /* firstly we process all strings. This is done because [{} and ] aren't escaped in strings, which complicates an iterative parse. */
   WHILE 1 = 1 /* forever until there is nothing more to do */
   BEGIN
     SELECT @start = PATINDEX('%[^a-zA-Z]["]%', @json collate SQL_Latin1_General_CP850_Bin); /* next delimited string */
     IF @start = 0 BREAK /*no more so drop through the WHILE loop */
     IF SUBSTRING(@json, @start+1, 1) = '"'
     BEGIN  /* Delimited name */
      SET @start = @start+1;
      SET @end = PATINDEX('%[^\]["]%', RIGHT(@json, LEN(@json+'|')-@start) collate SQL_Latin1_General_CP850_Bin);
     END
 
     IF @end = 0 /*no end delimiter to last string*/
      BREAK /* no more */
 
     SELECT @token = SUBSTRING(@json, @start+1, @end-1)
 
     /* now put in the escaped control characters */
     SELECT @token = REPLACE(@token, from_string, to_string)
     FROM
     (
      SELECT '\"' AS from_string, '"' AS to_string
      UNION ALL
      SELECT '\\', '\'
      UNION ALL
      SELECT '\/', '/'
      UNION ALL
      SELECT '\b', CHAR(08)
      UNION ALL
      SELECT '\f', CHAR(12)
      UNION ALL
      SELECT '\n', CHAR(10)
      UNION ALL
      SELECT '\r', CHAR(13)
      UNION ALL
      SELECT '\t', CHAR(09)
     ) substitutions
 
     SELECT @result = 0, @escape = 1
 
     /*Begin to take out any hex escape codes*/
     WHILE @escape > 0
     BEGIN
      /* find the next hex escape sequence */
      SELECT
        @index = 0, 
        @escape = PATINDEX('%\x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]%', @token collate SQL_Latin1_General_CP850_Bin)
 
      IF @escape > 0 /* if there is one */
      BEGIN
        WHILE @index < 4 /* there are always four digits to a \x sequence  */
        BEGIN
          /* determine its value */
          SELECT
           @result =
           @result + POWER(16, @index) * (CHARINDEX(SUBSTRING(@token, @escape + 2 + 3 - @index, 1), @characters) - 1), @index = @index+1 ;
          END
 
          /* and replace the hex sequence by its unicode value */
          SELECT @token = STUFF(@token, @escape, 6, NCHAR(@result))
        END
      END
 
      /* now store the string away */
      INSERT INTO @strings
      (stringvalue)
      SELECT @token
 
      /* and replace the string with a token */
      SELECT @json = STUFF(@json, @start, @end + 1, '@string' + CONVERT(nvarchar(5), @@identity))
     END
 
     /* all strings are now removed. Now we find the first leaf. */
     WHILE 1 = 1  /* forever until there is nothing more to do */
     BEGIN
      SELECT @parent_id = @parent_id + 1
     
      /* find the first object or list by looking for the open bracket */
      SELECT @firstobject = PATINDEX('%[{[[]%', @json collate SQL_Latin1_General_CP850_Bin)  /*object or array*/
 
      IF @firstobject = 0
        BREAK
 
      IF (SUBSTRING(@json, @firstobject, 1) = '{')
        SELECT @nextclosedelimiterChar = '}', @type = 'object'
      ELSE
        SELECT @nextclosedelimiterChar = ']', @type = 'array'
     
      SELECT @opendelimiter = @firstobject
 
      WHILE 1 = 1 --find the innermost object or list...
      BEGIN
        SELECT @lenjson = LEN(@json+'|')-1
        /* find the matching close-delimiter proceeding after the open-delimiter */
        SELECT @nextclosedelimiter = CHARINDEX(@nextclosedelimiterChar, @json, @opendelimiter + 1)
 
        /* is there an intervening open-delimiter of either type */
        SELECT @nextopendelimiter = PATINDEX('%[{[[]%',RIGHT(@json, @lenjson-@opendelimiter) collate SQL_Latin1_General_CP850_Bin) /*object*/
        IF @nextopendelimiter = 0
          BREAK
       
        SELECT @nextopendelimiter = @nextopendelimiter + @opendelimiter
       
        IF @nextclosedelimiter < @nextopendelimiter
          BREAK
       
        IF SUBSTRING(@json, @nextopendelimiter, 1) = '{'
          SELECT @nextclosedelimiterChar = '}', @type = 'object'
        ELSE
          SELECT @nextclosedelimiterChar = ']', @type = 'array'
       
        SELECT @opendelimiter = @nextopendelimiter
      END
 
     /* and parse out the list or name/value pairs */
     SELECT @contents = SUBSTRING(@json, @opendelimiter+1, @nextclosedelimiter-@opendelimiter - 1)
 
     SELECT @json = STUFF(@json, @opendelimiter, @nextclosedelimiter - @opendelimiter + 1, '@' + @type + CONVERT(nvarchar(5), @parent_id))
 
     WHILE (PATINDEX('%[A-Za-z0-9@+.e]%', @contents collate SQL_Latin1_General_CP850_Bin)) <  > 0
     BEGIN /* WHILE PATINDEX */
      IF @type = 'object' /*it will be a 0-n list containing a string followed by a string, number,boolean, or null*/
      BEGIN
        SELECT @end = CHARINDEX(':', ' '+@contents) /*if there is anything, it will be a string-based name.*/
        SELECT @start = PATINDEX('%[^A-Za-z@][@]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin) /*AAAAAAAA*/
 
        SELECT
          @token = SUBSTRING(' '+@contents, @start + 1, @end - @start - 1),
          @endofname = PATINDEX('%[0-9]%', @token collate SQL_Latin1_General_CP850_Bin),
          @param = RIGHT(@token, LEN(@token)-@endofname+1)
 
        SELECT
          @token = LEFT(@token, @endofname - 1),
          @contents = RIGHT(' ' + @contents, LEN(' ' + @contents + '|') - @end - 1)
 
        SELECT @name = stringvalue
        FROM @strings
        WHERE string_id = @param /*fetch the name*/
 
      END
      ELSE
      BEGIN
        SELECT @name = null
      END
 
      SELECT @end = CHARINDEX(',', @contents)  /*a string-token, object-token, list-token, number,boolean, or null*/
 
      IF @end = 0
        SELECT @end = PATINDEX('%[A-Za-z0-9@+.e][^A-Za-z0-9@+.e]%', @contents+' ' collate SQL_Latin1_General_CP850_Bin) + 1
 
      SELECT @start = PATINDEX('%[^A-Za-z0-9@+.e][A-Za-z0-9@+.e]%', ' ' + @contents collate SQL_Latin1_General_CP850_Bin)
      /*select @start,@end, LEN(@contents+'|'), @contents */
 
      SELECT
        @value = RTRIM(SUBSTRING(@contents, @start, @end-@start)),
        @contents = RIGHT(@contents + ' ', LEN(@contents+'|') - @end)
    
      IF SUBSTRING(@value, 1, 7) = '@object'
        INSERT INTO @hierarchy (name, parent_id, stringvalue, object_id, valuetype)
 
        SELECT @name, @parent_id, SUBSTRING(@value, 8, 5),
        SUBSTRING(@value, 8, 5), 'object'
 
      ELSE
        IF SUBSTRING(@value, 1, 6) = '@array'
          INSERT INTO @hierarchy (name, parent_id, stringvalue, object_id, valuetype)
 
          SELECT @name, @parent_id, SUBSTRING(@value, 7, 5), SUBSTRING(@value, 7, 5), 'array'
 
        ELSE
          IF SUBSTRING(@value, 1, 7) = '@string'
          INSERT INTO @hierarchy (name, parent_id, stringvalue, valuetype)
         
          SELECT @name, @parent_id, stringvalue, 'string'
          FROM @strings
          WHERE string_id = SUBSTRING(@value, 8, 5)
         
          ELSE
           IF @value IN ('true', 'false')
             INSERT INTO @hierarchy (name, parent_id, stringvalue, valuetype)
             
              SELECT @name, @parent_id, @value, 'boolean'
 
           ELSE
              IF @value = 'null'
              INSERT INTO @hierarchy (name, parent_id, stringvalue, valuetype)
              
              SELECT @name, @parent_id, @value, 'null'
       
              ELSE
               IF PATINDEX('%[^0-9]%', @value collate SQL_Latin1_General_CP850_Bin) > 0
                 INSERT INTO @hierarchy (name, parent_id, stringvalue, valuetype)
 
                 SELECT @name, @parent_id, @value, 'real'
 
               ELSE
                 INSERT INTO @hierarchy (name, parent_id, stringvalue, valuetype)
 
                 SELECT @name, @parent_id, @value, 'int'       
     END /* WHILE PATINDEX */
   END /* WHILE 1=1 forever until there is nothing more to do */
 
   INSERT INTO @hierarchy (name, parent_id, stringvalue, object_id, valuetype)
   SELECT '-', NULL, '', @parent_id - 1, @type
 
   RETURN
 
END
