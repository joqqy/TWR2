

struct xmlStruct
(
	isRoot = false,	
	
	rootName = undefined,
	
	nodeName = undefined,
		numChildren = 0,
		children = #(),
	parentName = undefined,
	
	attribs = #(#(),#()),	
	
	depth = 0,
	idx = 0,
	parentIDX = #()
)

struct read_xml
(
	str_xmlStruct,
	report = false,
	
	xmldoc,
	docEle,
	rootName = undefined,
	
	rootChildrenIDX = 0,
	rootChildrenIDX_2 = 0,
	
	rootIDX = undefined,
	depth = 0,
	idx = 0,
	depthArr = #(),
	numRecurse = 0,
	
	_xml_template = #(),
	_xml = #(),	
	
	attribName,
	attribValue,
	
	attribN,
	attribV,
	
	--format indents for tree level
	fn format_tabs depth = ( for i=1 to depth do format "\t" ),
	
	fn get_Nested_def \
								theNode =
	(
		attribN = undefined
		attribV = undefined
		
		--/*
		for n=0 to theNode.attributes.count-1 do
		(
			attribN = theNode.attributes.itemof[n].name
			attribV = theNode.attributes.itemof[n].value
			
			rootP = getinisetting CONST_CONFIG_PATH "root" "rootpath" --get the rootpath from the ini
			
			refPath = pathConfig.appendpath rootP attribV --construct the final path
			
			format "attribN: %\n" attribN
			format "attribV: %\n" attribV
			
			--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//
			if attribN == "definition" AND (doesfileexist refPath) then
			(
				if (doesfileexist refPath) then
				(
					arrDef = #() --reset array
			
					str_read_xml = read_xml()
					str_read_xml.report = true
			
					--read definition
					arrDef = str_read_xml.main \
														refPath \
														str_read_xml._xml
					
					--format "attribV:% \n" refPath
					--Append VARIANT_MESH_REFERENCE_array arrDef
				)
			)
			--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//			
		)
		--*/
	),
	
	--get the attributes
	fn get_Attribs \
						theNode \
						xml_arr =
	(
		attribName = undefined
		attribValue = undefined
		
		for n=0 to theNode.attributes.count-1 do
		(
			attribName = theNode.attributes.itemof[n].name
			attribValue = theNode.attributes.itemof[n].value			
			
			Append str_xmlStruct.attribs[1] attribName
			Append str_xmlStruct.attribs[2] attribValue
			
			if report then
			(
				--REPORT
				----------------depth format
				format_tabs depth
				format " --m_attribName: %\n" attribName
				----------------depth format
				format_tabs depth
				format " --m_attribValue: %\n" attribValue
			)
		)
	),
	
	--recurse function
	fn recurse \
					children \
					xml_arr =
	(
		numRecurse += 1		
		
		----------------depth add
		depth += 1										
		
		children = children.childnodes	
		
		childNum2 = undefined --the count of the child
		childName = undefined
		parentNode = undefined
		parentName = undefined
		
		for x=0 to children.count-1 do
		(			
			------------------------------------------------------------------------------------
			if x == 0 then
			(
				rootChildrenIDX_2 += 1
			)
			------------------------------------------------------------------------------------
			
			child = children.itemof[x]
			childNum2 = children.itemof[x].childnodes.count --the count of the child
			childName = child.name
			parentNode = child.parentNode
			parentName = child.parentNode.name
			
			----array append----
			str_xmlStruct = xmlStruct() --create instance
				str_xmlStruct.rootName = rootName
				str_xmlStruct.numChildren = childNum2
				str_xmlStruct.nodeName = childName
				str_xmlStruct.parentName = parentName
				str_xmlStruct.depth = depth
			
			/*
			--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//
			if childName == "VARIANT_MESH_REFERENCE" then
			(
				--get attribs
				get_Nested_def \												
										child			
			)
			--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//
			--*/

			
				Append str_xmlStruct.parentIDX rootIDX --always zero, this is the root index
					Append str_xmlStruct.parentIDX idx --children directly under root
						Append str_xmlStruct.parentIDX rootChildrenIDX
							if depth > 2 then
							(
								Append str_xmlStruct.parentIDX (rootChildrenIDX_2) --idx
								Append str_xmlStruct.parentIDX (x+1) --children count
							)			
			
			if report then
			(
				--REPORT
				----------------depth format
				format_tabs depth
				format "\n"
				
				--print tree index level
				format_tabs depth
				
				for d=1 to depth do
				(				
					format "%." str_xmlStruct.parentIDX[d]					
				)				

				--format the name of the node
				format "%. Name: %\t(parent: %)\n" (x+1) childName parentName
			)
	
			--get attribs
			get_Attribs \
							child \ 
							xml_arr			
			
			Append xml_arr str_xmlStruct
			
			--the recurse 2
			recurse \
						child \
						xml_arr					

		)
		----------------depth substract
		depth -= 1
	),
	
	fn csharp_assembly \
								xmlPath =
	(
		--------------------------------Create the dotNet xmlDoc----------------------------
		--Load the xml assemply
		dotNet.loadAssembly "system.xml"
		
		--Create an xml document object.
		xmldoc = dotnetobject "System.XML.XMLDocument"

		--This is the Root of the XML
		if template != "" then
		(
			xmldoc.Load xmlPath
		)
		return xmldoc.documentElement
	),
	
	fn main \
				xmlPath \
				xml_arr =
	(
		docEle = (csharp_assembly xmlPath)
		
		--read the root and get inside the xml to read the rest via the recurse function
		if docEle !=undefined then
		(
			xml_arr = #()			
			
			rootIDX = 0
			
			if report then
			(
				rootName = docEle.name
				format "%. Root: %\n" rootIDX rootName --->>>
			)
			
				---- array append ( this is the root - only one ofcourse) ----
				str_xmlStruct = xmlStruct()
					str_xmlStruct.rootName = rootName
					str_xmlStruct.isRoot = true
					Append str_xmlStruct.parentIDX rootIDX
				Append xml_arr str_xmlStruct
			
			--first pass the root to get its children (if there arent any children to the root, we cannot go in here)
			if docEle.childnodes.count > 0 then
			(
				----------------depthadd
				depth += 1
				
				--recurse through each of the root children -- it will go as deep as it needs to
				for n=0 to docEle.childnodes.count-1 do
				(
					child = docEle.childnodes.itemof[n]
					childName = child.name
					
					if report then
					(
						--REPORT
						----------------depth format
						format_tabs depth
						format "\n"
						----------------depth format
						format_tabs depth
						format "%.%. Name: %\n" rootIDX (n+1) childName --->>>
					)
					
					idx += 1
					
					----array append----
					str_xmlStruct = xmlStruct()
						str_xmlStruct.nodeName = childName
						str_xmlStruct.numChildren = docEle.childnodes.count
						Append str_xmlStruct.children childName
						str_xmlStruct.parentName = child.parentNode.name
						str_xmlStruct.depth = depth
					
						Append str_xmlStruct.parentIDX rootIDX
						Append str_xmlStruct.parentIDX idx
					
						if rootChildrenIDX > 0 then
						(
							Append str_xmlStruct.parentIDX rootChildrenIDX
						)						
					
						--get attribs
						get_Attribs \
										child \ 
										xml_arr					

					Append xml_arr str_xmlStruct
					
					rootChildrenIDX += 1 --the index of the children directly under the Root
					
					recurse \
								child \
								xml_arr
				)
				depth -= 1
			)
		)
		
		return xml_arr;
	)
)

/*
--///////////////////////////// Read XML ////////////////////////////////
str_read_xml = read_xml()
str_read_xml.report = true

--read template
-- str_read_xml.main \
-- 							xml_template \
-- 							str_read_xml._xml_template
--read definition
arr = str_read_xml.main \
							xml_definition \
							str_read_xml._xml
--////////////////////////////////////////////////////////////////////////

print arr


REPORT
for i=1 to str_read_xml._xml.count do
(
	str_read_xml.format_tabs str_read_xml._xml[i].depth
	print str_read_xml._xml[i]
)
--*/
