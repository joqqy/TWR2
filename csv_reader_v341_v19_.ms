resetMaxFile #noPrompt
actionMan.executeAction 0 "40829" --Show statistics
actionMan.executeAction 0 "40608"  -- Views: Viewport Selection Display Selected With Edges Faces Toggle


--Include XML (variantmeshdefinition) reader
filein @"xml_MeshDefReader_v4_.ms"

texture_array_suffix = ".texture_array"

safe2rotate = false
masterRead = false

--the ini config file (this can be changed to a location where you have read & write permissions - default is set to your system temp dir)
CONST_CONFIG_PATH = (pathConfig.appendPath sysInfo.tempdir "config.ini")

tga2dds = true --initial data (can be changed via the UI)

noUVs = false

--the root to all assets which is ...something\data
rootPath = (getinisetting CONST_CONFIG_PATH "root" "rootpath") --If the specified file, section, or key is not found, an empty string "" is returned.

--array used for filling and storing the listing the animations (the large listbox)
animList_arr = #()

--array used for filling and storing the Info listbox
info = #()

--array used for listing and storing files found in a folder
xmlVariantFiles_arr = #()

config_array = #()

struct sorted_varMeshRef
(
	_type					= undefined,
	_idx						= #(),
	_raw_paths				= #(),
	_separated_paths	= #(),
	_parentName			= #(),
	_parentVal				= #(),
	
	_NESTED				= #(),
		_nested_test		= #(),
	
	_randInt					= undefined,
	_randInt_crest		= undefined,	
	
	_random					= "",
	_random_crest		= "",
	
	_attach_points		= #(),
	_attach_crests		= #(),
	
	_hasDecals				= false, --default is false
	_subsHaveDecals		= false,
	_decalMaps				= #()
)

MESH_NODES_4_attachPoints_arr = #()
struct meshNodes_4_attachPoints
(
	_masterMeshNodes	= #(#(),#()),  --meshNode (to be filled in meshbuilder)
	_subMeshNodes		= #(#(),#())   --meshNode (to be filled in meshbuilder)
)
_attach_boneNumber_arr = #()

--The array of the read variantmeshdefinition xml - read, sorted and prepared
SEPARATED_DEFS_ARR = #()
--------------------------------------------------------------------------------------------------------------------------------------------------
--this is always the root bone if a bones rig/system exists
--root_bone = bones_array[1]
animateRoot = true

g_rmv2 = "" --the filename of the mesh (full path) (we may have to change this to something like "bodyparts" etc in accordance with the node naming in the variantmeshdefinition xml files)

struct rigging_data
(
	g_rmv2 = "",
	mesh_name = #(),
	skeleton_name = #(),	
	animation_name = ""	
)
--create instance (there is only one of this, and it may grow as we want more info in it)
str_rigging_data = rigging_data()

animFragmentList_arr = #(#(),#())
--------------------------------------------------------------------------------------------------------------------------------------------------
meshes_to_texture = #(#(),#())
mesh2_rig_animate_arr = #(#(),#())

	

data_array = #( \		
						#(), 				\	-- [1] _prefix subinfo headers description
						#(#(),#()), 	\	-- [2] submesh chunk description [2][1]master [2][2]subs
						#(#(),#()), 	\	-- [3] parsed mesh chunk
						#(#(),#()), 	\	-- [4] texture paths ---------------------------------------------------------
						#(#(),#()), 	\	-- [5] attach_points
						#(),			 	\	-- [6] header ( only 1 for each file)
						#(),			 	\	-- [7] built mesh node in [1] and its attach points
						#(#(),#()),	\	-- [8] have attachpoints
						#()	  			\ 	-- [9][1] Mesh Nodes	[9][n][1] = masterMesh Node		[9][n][2] = The submesh Nodes belonging to the masterMesh
					)
rootData = #(
					#(), -- path to mesh file
					#(), 		-- the data_array for this file (see the array above)
					#()  -- SEPARATED_DEFS_ARR
					)


--array containing the bones
bones_array = #()
					
skeleton_type_arr = #()
					
texturePaths_arr = #(#(),#())


	
--//////////////////////////////////// Mesh and Animation Parsing ////////////////////////////////////
const_fileOffset_type5	= 0x0000008C --140 (count starts from fileoffset 0)
const_fileOffset_type6	= 0x0000010C --268 (count starts from fileoffset 0)
const_fileOffset_type1	= 0x00000224 --548 (count starts from fileoffset 0) --skybox


		


--///////////////////////////// Functions /////////////////////////////
fn convertTo32 input16 =
(
	inputAsInt = input16
	sign = bit.get inputAsInt 16
	exponent = (bit.shift (bit.and inputAsInt (bit.hexasint "7C00")) -10) as integer - 16
	fraction = bit.and inputAsInt (bit.hexasint "03FF")
	
	if sign == true then
	(
		sign = 1
	)
	else
	(
		sign = 0
	)
	
	exponentF = exponent + 127
	--Ouput 32 bit integer representing a 32 bit float
	outputAsFloat = bit.or (bit.or (bit.shift fraction 13) (bit.shift exponentF 23)) (bit.shift sign 31)
	
	--Output Check	
	return bit.intasfloat outputasfloat
)

fn readHalfFloat fstream =
(
    hf = readshort fstream #unsigned
    sign = bit.get hf 16
    exponent = (bit.shift (bit.and hf (bit.hexasint "7C00")) -10) as integer - 16
    fraction = bit.and hf (bit.hexasint "03FF")
    
	if sign==true then
	(
		sign = 1
	)	
	else
	(
		sign = 0
	)		
    
	exponentF = exponent + 127
    outputAsFloat = bit.or (bit.or (bit.shift fraction 13) (bit.shift exponentF 23)) (bit.shift sign 31)    
	
	return bit.intasfloat outputasfloat*2
)

fn ReadFixedString \
							bstream \
							fixedLen =
(
	if bstream != undefined then
	(	
		local str = ""
		for i = 1 to fixedLen do
		(
			str += bit.intAsChar (ReadByte bstream #unsigned)
		)
		
		return str
	)
)
--///////////////////////////// End of Functions /////////////////////////////

--//notes
-- double underscore __ indicates unknown (an entity that hasn't been decoded yet)

--////////////////////// Variable Declarations //////////////////////
------------ Constants --------------
_HEADER = "RMV2"
--------- End of Constants ---------

------------ Structs --------------
--// 1 per file
struct header
(
	headerString			= "", --4 byte string
	fileType					= 0, --int
	numMeshes				= 0, --int --//This might be synonymous with the number of LODs
	
	--//SKELETON NAME this is likely the filename(extension not included) of the 	.bone_inv_trans_mats 	& 	.anim in 	..data\animations\skeletons
	skeleton_type			= undefined, --string, not sure how long this is, but entire chunks seems to always be 128 bytes
	
	meshFilePath			= ""
)
--so we get access to the header, which is always just one per file
str_header = header()

--// 1 per file
struct subMesh_headers
(
	--const_fileOffset_type5 = 140, --this is probably a constant, so far it holds true for type 6
	
	_prefix							= 0,	
	
	sizeOfGeomChunk				= 0, --int
	sizeOfFaceChunk				= 0, --int
	fileOffset_subMeshDescr	= 0, --int offset to add to the first fileoffset
	_padding						= 0 --int
)

--// For each master mesh and subsubm
--after the 0x41000000 or similar (i.e. the subMesh header description)
struct subMeshDescription
(
	fileOffset_subMeshDescr				= undefined,
	subStart										= undefined,
	
	meshChunk_type							= 0, --int to check for 0x41000000 (65)
	--meshChunk_prefix = undefined, -- int before the actual meshChunk
	
	fileoffset_next_subChunk				= 0,
	fileOffset_vertexPos						= 0, --int (count from meshChunk_type )
	numVerts									= 0, --int
	fileOffset_faceIndices					= 0, --int (count from meshChunk_type )
	halfNumFaceIndices						= 0, --int face indices chunk size / 2 (not sure why)	
	
		__u1										= 0.0, --float (unknown)
		boundingBox_2verts					= #(),
	strLen_shaderType_type6				= 12, --bytes
		strLen_shaderType_type6_2		= 16, --bytes		
	strLen_shaderType_type5				= 24, --bytes
	strLen_shaderType_type5_43			= 64, --bytes
	strLen_shaderType_type5_40			= 64, --bytes
	--shaderType = "", --string ( 12 bytes ??? )
	
	shaderType									= "", --string ( 16 bytes ??? )
	shaderType_2								= "", --string ( 16 bytes ??? )
		
		--0x0003 = Game (28 bytes per pos chunk) 
		--0x0004 = CINE (32 bytes per pos element)	
		--0x0000 Siege ramps (32 bytes per pos element) (Rigidmodels, not variantmeshes)
		prefix_GAME3_CINE4_RIGID0		= undefined, --int16
		
		uA											= #(), --unknown int
	
	strLen_unknownString					= 16, --bytes
	unknownString								= "", --unknown String
	
		__u2										= 0, --float (unknown)

	jump_type6									= 22,
	jump_type5									= 42,
		jump_type5_2							= 16,
		uString_type5_2						= "", --16 bytes
		destruct_type5						= "", --64 bytes
	
	strlLen_groupName_type6				= 32, --bytes
	strlLen_groupName_type5				= 64, --bytes
	strlLen_groupName_type5_43			= 512, --bytes
	strlLen_groupName_type5_40			= 64, --bytes
		groupName								= "", --string ( 32 bytes ??? )
	
	strLen_texPath_type6					= 256, --bytes
	strLen_texPath_type5					= 512, --bytes
	strLen_texPath_type5_40				= 1024, --bytes
	texPath										= "", --string ( 256 bytes ??? )
		_padding_type6						= 256, --256 byte padding
		_padding_type5						= 512, --512 byte padding	
	
	unknownMatrix							= undefined,
	
	textureInfoOffset							= 0
)

--// For each master mesh and subsubm
struct unknownMatrix --maybe identity matrices, not sure though
(
	__u1 = 0, --int16 (unknown)
	
	matrixCount = 13, --number of matrices to read (each element is a float)
	_matrix3 = Matrix3 1, --declare matrix
	matrix3_arr = #(),
		_padding = 4, --bytes
	
	FF_flags_arr = #() --store the 0xFFFF flags here, should and must be 2 of them, and both must be == -1
)

--// For each master mesh and subsubm
struct texturePaths
(	
	numTextures				= 0, --int
	
		_bones					= #(),
	
		attachPoints_arr		= #(), --this will contain each attachpoint array read
	
		_padding2				= 2, --int
		_padding3				= 128, --bytes
	
		__u1						= 0, --int
	
	texPaths_arr				= #(#(), #()),
	
	--loop the numTextures here
	texType						= 0, --int
	strLen_texPath_type6	= 256, --bytes
	strLen_texPath_type5	= 512, --bytes
	texPath						= "" --string
)

--// For each master mesh and subsubm
struct weights
(
	bone1			= 0,
	bone2			= 0,
	
	weight			= 0,	--game
	
	weightA			= 0,	--cine
	weightB			= 0,	--cine
	
	weight1			= 0,	--cine
	weight2			= 0	--cine
)

--// For each master mesh and subsubm
struct geomChunk
(
	subSubM_Prefix_arr			= #(),
	_padding1						= 1, --int
	
	--NOTE first we must jump 156 bytes (and I think this is a constant across the rigid model files at least)
	
	--in the mesh header mesh chunk info we see the type: 
	--0x00000000, 0x00000001 (most common), 0x00000021, 0x00000007, 0x00000004
	--and in rigid models I have seen 0x00000002 together with the 0x00000001
	--0x0000001F, 0x0000001C, 0x00000019 (bam_citadel_piece01_destruct01.rigid_model_v2) (this also has the unusual mesh type of 0x0000003F)
	-- what do the types mean?	
	flag1								= 0,	
	
	weights_arr						= #(), --original

	verts								= #(),
	unknown						= #(),
	normals							= #(),
	uvw								= #(),
	unknown2						= #(),
	
	faces								= #()
)
--------- End of Structs ---------

--Begins reading the file at offset 0x00000000
fn fill_header \
					bstream \
					str_2Fill =
(
	if bstream != undefined then
	(	
		str_2Fill.headerString = ReadFixedString \
																bstream \
																4
		
		--str_2Fill.meshType = readlong bstream
		str_2Fill.fileType = readlong bstream
		str_2Fill.numMeshes = readlong bstream
		
		if str_2Fill.fileType == 0x00000006 then -- TYPE 0x00000006
		(
			str_2Fill.skeleton_type = readstring bstream
		)
		else if str_2Fill.fileType == 0x00000005 then -- TYPE 0x00000005
		(
			str_2Fill.skeleton_type = ReadFixedString \
																	bstream \
																	128
		)	
	)
)

--the _prefixes sub info
fn fill_subMesh_headers \
									bstream \
									data_array \
									str_info =
(	
	--look up the meshtype and make a jump accordingly
	if str_info.fileType == 0x00000006 then
	(
		--jump to the fileOffset, which for this chunk is always the same (140 bytes for rigid models, and possibly other formats as well)
		fseek bstream const_fileOffset_type5 #seek_set
	)
	else if str_info.fileType == 0x00000005 then
	(
		--jump to the fileOffset, which for this chunk is always the same (140 bytes for rigid models, and possibly other formats as well)
		fseek bstream const_fileOffset_type6 #seek_set		
	)
	
	--format "_______________________+++++_______________________%\n" (ftell bstream)
	---------------------------------////// Likely that this part below is the same for all files, thus need no conditional check ////////////!!!!!!
	if str_info.numMeshes > 0 then
	(
		for i=1 to str_info.numMeshes do
		(
			str_2Fill										= subMesh_headers() --create struct instance
			str_2Fill._prefix							= readlong bstream --Number of sub-sub meshes

			str_2Fill.sizeOfGeomChunk				= readlong bstream
			str_2Fill.sizeOfFaceChunk				= readlong bstream
			str_2Fill.fileOffset_subMeshDescr	= readlong bstream
			str_2Fill._padding							= readfloat bstream

			Append data_array[1] str_2Fill
		)
	)
)

fn REPORT_groupType \
								type =
(
	case of
	(
		--// Actor
		(type == 0x00000052): \
		(
			format "Mesh is of type Actor\n"								
		)
		--// Banner
		(type == 0x0000001A): \
		(
			format "Mesh is of type Banner\n"								
		)
		--// Bow
		(type == 0x00000040): \
		(
			format "Mesh is of type Banner\n"								
		)
		--// Building - Acropolis
		(type == 0x00000056): \
		(
			format "Mesh is of type Building - Acropolis\n"								
		)
		--// Building - Generic
		(type == 0x00000044): \
		(
			format "Mesh is of type Building - Generic\n"								
		)
		--// Building - Generic
		(type == 0x0000003C): \
		(
			format "Mesh is of type Cloak\n"								
		)
		--// Animal
		(type == 0x00000041): \
		(
			format "Mesh is of type Animal\n"								
		)
		--// Animal - Dog
		(type == 0x00000001): \
		(
			format "Mesh is of type Animal - Dog\n"								
		)
		--// Plant A
		(type == 0x0000004A): \
		(
			format "Mesh is of type Plant A\n"								
		)
		--// Plant B
		(type == 0x0000004B): \
		(
			format "Mesh is of type Plant B\n"								
		)
		--// Projectile
		(type == 0x00000046): \
		(
			format "Mesh is of type Projectile\n"								
		)
		--// Shield
		(type == 0x00000048): \
		(
			format "Mesh is of type Shield\n"								
		)
		--// Statue A
		(type == 0x00000036): \
		(
			format "Mesh is of type Statue A\n"								
		)
		--// Statue B
		(type == 0x00000039): \
		(
			format "Mesh is of type Statue B\n"								
		)
		--// Tunic
		(type == 0x0000004F): \
		(
			format "Mesh is of type Tunic B\n"								
		)
		--// Wave
		(type == 0x00000016): \
		(
			format "Mesh is of type Wave B\n"								
		)
	)
)


fn meshChunkType_fill \
								bstream \
								header_info \								
								str_2Fill =
(	
	--format "<<<<<<<<<<<<<<<<<<<<<<<<<<<<< % >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n" (ftell bstream)	
	
	-- the eg 0x00000044 or (other variants)
	meshChunk_type = str_2Fill.meshChunk_type
	
	--check if we must skip UVs, default = true (DECALS and VFX) I have no interest for these really
	if meshChunk_type == 0x00000043 then --there may be more than 0x00000043 (not even sure if 0x00000043 actually does have UVs)
	(
		noUVs = true
	)
	
	--read		AFTER	0x00000044  (or submesh types variants )
	str_2Fill.fileOffset_subMeshDescr		= ((ftell bstream)-4) --((this + the const offset)-facechunkSize = fileoffset to faceChunk)
	str_2Fill.fileoffset_next_subChunk		= readlong bstream --((this + the const offset)-facechunkSize = fileoffset to faceChunk)
	str_2Fill.fileOffset_vertexPos				= readlong bstream --(this + offset of the current 0x00000044 or similar = fileoffset to the pos chunk)
	str_2Fill.numVerts							= readlong bstream
	str_2Fill.fileOffset_faceIndices			= readlong bstream --(this + the const offset= fileoffset to faceChunk)
	str_2Fill.halfNumFaceIndices				= readlong bstream	--facechunkSize / 2 (not sure why)
	
	for i=1 to 2 do
	(
		x = readfloat bstream
		y = readfloat bstream
		z = readfloat bstream
				
		Append	str_2Fill.boundingBox_2verts	[x,y,z]
	)	
	
	if header_info.fileType == 0x00000006 then ------------+++++ TYPE 6 +++++------------
	(
		str_2Fill.shaderType								= trimleft (trimright (ReadFixedString (bstream) (str_2Fill.strLen_shaderType_type6))) --12 bytes --usually "default_dry"			
			Append			str_2Fill.uA					(readlong bstream)		
			str_2Fill.shaderType_2						= trimleft (trimright (ReadFixedString (bstream) (str_2Fill.strLen_shaderType_type6_2))) --16 bytes --usually "default_dry"				
			
			--REPORT
			--format "I am now inside the meshChunkType_fill READER and will just read prefix_GAME3_CINE4_RIGID0: %\n" (ftell bstream)				

			--0x0003 = Game (28 bytes per pos chunk) 
			--0x0004 = CINE (32 bytes per pos element)	
			--0x0000 Siege ramps (32 bytes per pos element) (Rigidmodels, not variantmeshes)			
			str_2Fill.prefix_GAME3_CINE4_RIGID0	= readshort bstream				
				
				
		str_2Fill.groupName								= trimleft (trimright (ReadFixedString (bstream) (str_2Fill.strlLen_groupName_type6)))		
		str_2Fill.texPath									= trimleft (trimright (ReadFixedString (bstream) (str_2Fill.strLen_texPath_type6)))		

		--jump 256 bytes
		for p=1 to str_2Fill._padding_type6 do
		(
			readbyte bstream
		)		
	)	
	else if header_info.fileType == 0x00000005 then ------------+++++ TYPE 5 +++++------------
	(		
		--format "_______________________+++++_______________________%\n" (ftell bstream)
		str_2Fill.shaderType								= ReadFixedString (bstream) (str_2Fill.strLen_shaderType_type5) --24 bytes
			
			for x=1 to 2 do Append str_2Fill.uA (readlong bstream) --unknown
		
		str_2Fill.groupName								= ReadFixedString (bstream) 32 --24 bytes		
			
			--0x0003 = Game (28 bytes per pos chunk) 
			--0x0004 = CINE (32 bytes per pos element)	
			--0x0000 Siege ramps (32 bytes per pos element) (Rigidmodels, not variantmeshes)
			str_2Fill.prefix_GAME3_CINE4_RIGID0	= readshort bstream	
		
		str_2Fill.destruct_type5						= ReadFixedString (bstream) (str_2Fill.strLen_shaderType_type5_40) --64 bytes		
		str_2Fill.texPath									= ReadFixedString (bstream) (str_2Fill.strLen_texPath_type5) --512, --bytes
		
		-- jump 512 bytes
		for p=1 to 512 do
		(
			readbyte bstream
		)
	)
	
	format "++++++++++++++++++++++++++++++++++ % ++++++++++++++++++++++++++++++++++\n" (ftell bstream)
)

fn fill_unknownMatrix \
								bstream \
								str_2Fill =
(
	str_2Fill.__u1 = readshort bstream
	
	for i=1 to str_2Fill.matrixCount do --13*float
	(
		x = readfloat bstream
		y = readfloat bstream
		z = readfloat bstream
		
		Append str_2Fill.matrix3_arr [x,y,z]
	)
	
	for i=1 to 2 do
	(
		FF_flags_arr = (readlong bstream)
		Append (str_2Fill.FF_flags_arr) (FF_flags_arr)
	)
	return str_2Fill
)

---------------------------------------------Attach Points stuff---------------------------------------------
attachPoints_arr = #()
struct attach_points
(	
	--NsubMesh = undefined,
		NsubMesh_arr				= #(),
	--thisNum = undefined,
		thisNum_arr				= #(),
	
	--variantMeshName = undefined,
		variantMeshNames_arr	= #(),
	--_name = undefined,
		_names_arr					= #(),
	
	belongs2skeleton = undefined,
		
	--numAttachPoints	= 0, --int
		numAttachPoints_arr	= #(), --int	
	
	--matrix = matrix3 1,
		matrices_arr				= #(),
	--attachBone = undefined	
		attachBones_arr			= #(),
	
	activeBones_arr				= #()
	
)
fn fill_texturePaths \
							bstream \
							header_info \
							data_array \
							meshCount \							
							str_2Fill =
(	
	numAttachPoints				= readlong bstream
	str_2Fill.numTextures		= readlong bstream
	
	format "____________numAttachPoints: %___________\n" numAttachPoints	
	format "____________numTextures: %___________\n" str_2Fill.numTextures
	format "____________meshCount: %\n___________\n" meshCount	
	
	activeAttachPoints = #()
	
	
	--/* --TEMP OFF
	if numAttachPoints > 0 then		
	(
		for i=1 to  35 do
		(
			Append str_2Fill._bones (readlong bstream)
		)
		
		str_attach_points = attach_points() --create instance for attach points
		
		--//////////////////////// Read the Attach Points ////////////////////////
		for i=1 to numAttachPoints do
		(	
			--str_attach_points = attach_points() --create instance for attach points
			
			
			
			--str_attach_points.numAttachPoints = numAttachPoints
				Append str_attach_points.numAttachPoints_arr numAttachPoints
			
			--str_attach_points.NsubMesh = header_info.numMeshes --------------------------------------------------------
				Append str_attach_points.NsubMesh_arr header_info.numMeshes --------------------------------------------------------
			
			--str_attach_points.thisNum = i
				Append str_attach_points.thisNum_arr i
			
			
			
			if ( header_info.skeleton_type != undefined) AND \
				(header_info.skeleton_type != "") then
			(
				str_attach_points.belongs2skeleton = header_info.skeleton_type --at this point, the skeleton_type has been read if any, and we can take it directly from the struct2Fill
			)
			
			--str_attach_points.variantMeshName = (filenameFromPath g_rmv2) ---<<<---	
				Append str_attach_points.variantMeshNames_arr (filenameFromPath g_rmv2)
									
			str = trimright (trimleft (ReadFixedString bstream 32))				
			--str_attach_points._name = str --<<<<---
				Append str_attach_points._names_arr str --<<<<---
							
			--Append arr[1] str	--the string name
							
			--// Read the matrix
			matrix = matrix3 1
			for n=1 to 1 do --for rows for the 4x4 matrix (really a 4x3 because the last column is added by max) -Note, this will be a TRANSPOSED matrix
			(
				--------------------
				matrix.row1.x = readfloat bstream
				matrix.row2.x = readfloat bstream
				matrix.row3.x = readfloat bstream
				matrix.row4.x = readfloat bstream

				matrix.row1.y = readfloat bstream
				matrix.row2.y = readfloat bstream
				matrix.row3.y = readfloat bstream
				matrix.row4.y = readfloat bstream

				matrix.row1.z = readfloat bstream
				matrix.row2.z = readfloat bstream
				matrix.row3.z = readfloat bstream
				matrix.row4.z = readfloat bstream
				------------------------------
			)						
			--str_attach_points.matrix = matrix ---<<<---
				Append str_attach_points.matrices_arr matrix ---<<<---
							
			attachBone = readlong bstream --read the bone to attach to (see google doc notes)	
			
			if str_2Fill._bones[i] != 0x00000000 then
			(
				Append activeAttachPoints attachBone
				Append str_attach_points.activeBones_arr attachBone
			)
			else
			(
				Append activeAttachPoints (-1)
				Append str_attach_points.activeBones_arr (-1)
			)
			
			--str_attach_points.attachBone = attachBone ---<<<---
				Append str_attach_points.attachBones_arr attachBone ---<<<---
			
			if masterRead != false then
			(
				Append data_array[5][1] str_attach_points							
			)
			else
			(
				Append data_array[5][2] str_attach_points	
			)
			
			--Append attachPoints_arr str_attach_points --extra global array, exactly the same as above			
		)
		--///////////////////// End of Read the Attach Points //////////////////////
	)	
	else if numAttachPoints == 0 then --// In case there are no attach points
	(
		for i=1 to  35 do
		(
			Append str_2Fill._bones (readlong bstream)
		)
	)	
	--format "_______________________(ftell bstream): %_______________________\n" (ftell bstream)
	--*/	
	
	Append attachPoints_arr str_attach_points --extra global array, exactly the same as above			
	Append _attach_boneNumber_arr activeAttachPoints
	
	
	
	for i=1 to str_2Fill.numTextures do
	(
		str_2Fill.texType = readlong bstream		
		
		if header_info.fileType == 0x00000006 then
		(
			--format "_______________________Textures_______________________%\n" (ftell bstream)
			texPath = ReadFixedString (bstream) (str_2Fill.strLen_texPath_type6)
			
			--make .tga files .dds
			if tga2dds == true then
			(
				if  getFilenameType texPath == ".tga" then
				(
					fileName = getFilenameFile texPath
					_path = getFilenamePath texPath -- returns: "myImage"
					
					texPath = (_path + fileName + ".dds")
				)
			)
			
				str_2Fill.texPath = texPath				
			Append str_2Fill.texPaths_arr[1] str_2Fill.texType
			Append str_2Fill.texPaths_arr[2] str_2Fill.texPath
		)
		else if header_info.fileType == 0x00000005 then
		(
			--format "_______________________Textures_______________________%\n" (ftell bstream)
			texPath = ReadFixedString (bstream) (str_2Fill.strLen_texPath_type5)
			
			--make .tga files .dds
			if tga2dds == true then
			(
				if  getFilenameType texPath == ".tga"  then
				(
					fileName = getFilenameFile texPath					
					_path = getFilenamePath texPath -- returns: "myImage"
					
					texPath = (_path + fileName + ".dds")
				)
			)			
			
				str_2Fill.texPath = texPath			
			Append str_2Fill.texPaths_arr[1] str_2Fill.texType
			Append str_2Fill.texPaths_arr[2] str_2Fill.texPath
		)
	)	
	
	return str_2Fill
)


----------------------------------------End of Attach Points stuff------------------------------------------
fn read_subSubmMesh_DescrChunk \
												bs \
												header_info \
												x \												
												data_array \
												str_unknownMatrix \
												str_texturePaths \
												str_2Fill =
(	
	str_2Fill.meshChunk_type = readlong bs --the kind of meshChunk, eg 0x00000044 or other
	
	REPORT_groupType str_2Fill.meshChunk_type
	
	--///////////////////////////////// Read the subSubM description /////////////////////////////////
	if str_2Fill.meshChunk_type == 0x00000043 then --only DECALS / VFX
	(			
		meshChunkType_fill \
									bs \
									header_info \									
									str_2Fill
	)		
	else
	(
		meshChunkType_fill \
									bs \
									header_info \									
									str_2Fill
						
		str_unknownMatrix = fill_unknownMatrix \
																bs \
																str_unknownMatrix
						
		str_2Fill.unknownMatrix = str_unknownMatrix
						
		str_2Fill.textureInfoOffset = (ftell bs) --the offset to the start of the texture info						

		str_texturePaths = fill_texturePaths \
															bs \
															header_info \
															data_array \
															x \															
															str_texturePaths
	)
	--////////////////////////////// End of Read the subSubM description //////////////////////////////
	
	format "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++�����������x: %\n" x
	format "str_texturePaths: %\n" str_texturePaths
	
	Append data_array[2][2][x] str_2Fill
	Append data_array[4][2][x] str_texturePaths
	--Append data_array[4][2][1] str_texturePaths --test
	--format "data_array[4][2][data_array[4][2].count]: %\n" data_array[4][2][data_array[4][2].count]
					
	--extra
	Append texturePaths_arr str_texturePaths
)

fn read_MasterMesh_DescrChunk \
												bs \
												header_info \
												x \												
												data_array \
												str_unknownMatrix \
												str_texturePaths \
												str_2Fill =
(

	fseek bs data_array[1][x].fileOffset_subMeshDescr #seek_set --jump to the start of the (first only) submMesh description (should be similar to 0x00000044 or similar)				
	str_2Fill.meshChunk_type = readlong bs --the kind of meshChunk, eg 0x00000044 or other
	
	REPORT_groupType str_2Fill.meshChunk_type
	
	--///////////////////////////////// Read the submesh description /////////////////////////////////
	if str_2Fill.meshChunk_type == 0x00000043 then --only DECALS / VFX
	(			
		meshChunkType_fill \
									bs \
									header_info \									
									str_2Fill
	)		
	else
	(
		meshChunkType_fill \
									bs \
									header_info \									
									str_2Fill
							
		str_unknownMatrix = fill_unknownMatrix \
																bs \
																str_unknownMatrix
							
		str_2Fill.unknownMatrix = str_unknownMatrix
						
		str_2Fill.textureInfoOffset = (ftell bs) --the offset to the start of the texture info
							

		str_texturePaths = fill_texturePaths \
															bs \
															header_info \
															data_array \
															x \															
															str_texturePaths
	)
	--////////////////////////////// End of Read the submesh description //////////////////////////////
	
	Append data_array[2][1][x] str_2Fill --add the subSubM mesh description info for the x master mesh
	Append data_array[4][1][x] str_texturePaths --add the subSubM texture info description info for the x master mesh
						
	--extra
	Append texturePaths_arr str_texturePaths
)


fn fill_SUB_subMeshDescription \
											bs \
											header_info \
											x \
											data_array =
(
		--//////////// Create struct instances ////////////
		str_2Fill					= subMeshDescription() --create struct instance
		str_unknownMatrix	= unknownMatrix() --create struct instance
		str_texturePaths		= texturePaths() --create struct instance
	

		read_subSubmMesh_DescrChunk \
													bs \
													header_info \
													x \															
													data_array \
													str_unknownMatrix \
													str_texturePaths \
													str_2Fill
)


fn fill_subMeshDescription \
									bs \
									header_info \
									x \
									data_array =
(	
	for x=1 to str_header.numMeshes do
	(
		Append data_array[2][1] #()
		Append data_array[4][1] #()

		--//////////// Create struct instances ////////////		
		str_unknownMatrix = unknownMatrix() --create struct instance
		str_texturePaths = texturePaths() --create struct instance
		str_2Fill = subMeshDescription() --create struct instance
		
		read_MasterMesh_DescrChunk \
													bs \
													header_info \
													x \															
													data_array \
													str_unknownMatrix \
													str_texturePaths \
													str_2Fill	
	)
)




--------------------------------'''''''''''''''''''''''''''''''''''''''''''''''''''''
--//////////////////////////////////////////////////// MESH PARSING FUNCTIONS ////////////////////////////////////////////////////
--//////////////////////////////////////////////////// TYPE 5 ////////////////////////////////////////////////////
--each meshChunk element is 32 bytes
-------------------------
fn type5_44_posReader \
									bs \
									nVerts \																					
									data_array \											
									header_info \											
									faceChunkOffset \
									numFaces \
									str_2Fill =
(
	--for i=1 to data_array[2][count][sx].numverts do
	for i=1 to nVerts do
	(
		--vertex
		x = readHalfFloat bs
		y = readHalfFloat bs	
		z = readHalfFloat bs
				
		--unknown
		u2 = readHalfFloat bs
				
		--UVs		
		u = readHalfFloat bs	
		v = readHalfFloat bs
		w = readHalfFloat bs	
			
		--unknown
		u3 = readHalfFloat bs
		u4 = readHalfFloat bs
		u5 = readHalfFloat bs
		u6 = readHalfFloat bs
		u7 = readHalfFloat bs
		u8 = readHalfFloat bs				
		u9 = readshort bs
		u10 = readshort bs
		
		--unknown
		u1 = readHalfFloat bs
		
		Append str_2Fill.verts [x,y,z] --fill vert array
		Append str_2Fill.uvw [u,(1-v),w*0] --fill uvw array
	)			

	fseek bs faceChunkOffset #seek_set --jump to meshChunk		
		
	--The entire faces chunk	
	for i=1 to (numFaces/3) do
	(
		a = (readshort bs)
		b = (readshort bs)
		c = (readshort bs)
					
		Append str_2Fill.faces [a+1,b+1,c+1]
	)		
)
--This are rigged and anim meshes for Cinematic variantmodels -this function handles 32 bytes per element
fn type5_44_meshParse \
									bs \
									nVerts \
									count \										
									data_array \
									header_info \
									str_2Fill =
(	
	if masterRead == false then
	(
		--These two will be used in the pos reader
		faceChunkOffset = data_array[2][1][count][1].fileOffset_faceIndices + data_array[1][count].fileOffset_subMeshDescr		
		numFaces = data_array[2][1][count][1].halfNumFaceIndices
		
		
		meshChunkOffset = (data_array[2][1][count][1].fileOffset_vertexPos + data_array[1][count].fileOffset_subMeshDescr)
		
		------------------------------------------
		fseek bs meshChunkOffset #seek_set --jump to meshChunk
		------------------------------------------
			
		format "******************************* READING THE MASTER MESH: %\n" (ftell bs)
		
		--------------------------------------------------------------
		type5_44_posReader \
										bs \
										nVerts \																			
										data_array \
										header_info \
										faceChunkOffset \
										numFaces \
										str_2Fill
		--------------------------------------------------------------
		
		masterRead = true
	)
	
	--prepare containers in the arrays
-- 	Append data_array[2][2] #()
-- 	Append data_array[4][2] #()
-- 	Append data_array[3][2] #()
	
	
	if (data_array[1][count]._prefix > 1) then --children to master mesh
	(		
		Append data_array[2][2] #()--!!??
		Append data_array[4][2] #()--!!??
		
		Append data_array[3][2] #()
		
		--------------------------------------------------------------
		 --children to master mesh (we subract 1 because 1 is the Master Mesh that we have already read above)
		for sx=1 to data_array[1][count]._prefix-1 do
		--for sx=1 to 2 do --temp
		(
			---------------------Seek the right fileoffset position to the submesh description---------------------
			if sx > 1 then
			(
				nextChunk = data_array[2][2][count][sx-1].fileoffset_next_subChunk + data_array[2][2][count][sx-1].fileOffset_subMeshDescr
				fseek bs nextChunk #seek_set
			)
			else if sx == 1 then
			(
				nextChunk = (data_array[2][1][count][1].fileoffset_next_subChunk + data_array[1][count].fileOffset_subMeshDescr)
				fseek bs nextChunk #seek_set
			)
			----------------------------------------------------------------------------------------------------------------
			
			fill_SUB_subMeshDescription \
													bs \
													header_info \
													count \
													data_array			
		)
		--------------------------------------------------------------		
		
		format "Count----: %\n" count
		

		for sx=1 to data_array[2][2][count].count do
		(
			next_subChunk				= data_array[2][2][count][sx].fileoffset_next_subChunk 
			fileOffset_vertPos			= data_array[2][2][count][sx].fileOffset_vertexPos
			cur_pos							= data_array[2][2][count][sx].fileOffset_subMeshDescr			
			nVerts 							= data_array[2][2][count][sx].numverts	
			faceChunkOffset				= (data_array[2][2][count][sx].fileOffset_faceIndices + cur_pos)
			numFaces						= data_array[2][2][count][sx].halfNumFaceIndices						

			fseek bs (fileOffset_vertPos+cur_pos) #seek_set		
						
			str_2Fill_2 = geomChunk()
				
				
						
	--	 	for px =1 to 10 do
	--	 	(
	--	 		prefix = readlong bs
	-- 			Append str_2Fill_2.subSubM_Prefix_arr prefix
	-- 		)						
				
			--REPORT		
-- 				format "count: %\n" count
-- 			format "*******will begin to read pos chunk here: %\n" (ftell bs)
-- 			format "___next_subChunk___: %\n" next_subChunk
-- 			format "___fileOffset_vertPos___: %\n" fileOffset_vertPos
-- 			format "___cur_pos___: %\n" cur_pos
-- 			format "___nVerts___: %\n" nVerts
-- 			format "___faceChunkOffset___: %\n" faceChunkOffset
-- 			format "___numFaces___: %\n\n" numFaces
						
						
			format "(ftell bs): %\n" (ftell bs)		
			--------------------------------------------------------------		
			type5_44_posReader \
											bs \
											nVerts \																											
											data_array \
											header_info \														
											faceChunkOffset \
											numFaces \
											str_2Fill_2
			--------------------------------------------------------------				
				
			Append data_array[3][2][count] str_2Fill_2				
		)
	)	
	masterRead = false
)
-------------------------

--////////////////////////////////////// DECALS / VFX //////////////////////////////////////
-- /// TYPE 5
--NO UVs, --!!?? -uncommon only - 16 bytes per pos element - 3 * float for x, y, z (12 bytes) - and 4 unknown bytes
-------------------------
fn type5_DECALS_VFX_posReader \
												bs \
												nVerts \																					
												data_array \											
												header_info \											
												faceChunkOffset \
												numFaces \
												str_2Fill =
(
	--for i=1 to data_array[2][count][sx].numverts do
	for i=1 to nVerts do
	(
		--vertex	
		x = readfloat bs
		y = readfloat bs	
		z = readfloat bs
		
			u1 = readfloat bs
		
		Append str_2Fill.verts [x,y,z]
		--Append str_2Fill.uvw [u,(1-v),w*0] --fill uvw array
	)			

	fseek bs faceChunkOffset #seek_set --jump to meshChunk		
		
	--The entire faces chunk	
	for i=1 to (numFaces/3) do
	(
		a = (readshort bs)
		b = (readshort bs)
		c = (readshort bs)
					
		Append str_2Fill.faces [a+1,b+1,c+1]
	)		
)
--This are rigged and anim meshes for Cinematic variantmodels -this function handles 32 bytes per element
fn type5_DECALS_VFX_meshParse \
												bs \
												nVerts \
												count \										
												data_array \
												header_info \
												str_2Fill =
(	
	if masterRead == false then
	(
		--These two will be used in the pos reader
		faceChunkOffset = data_array[2][1][count][1].fileOffset_faceIndices + data_array[1][count].fileOffset_subMeshDescr		
		numFaces = data_array[2][1][count][1].halfNumFaceIndices
		
		
		meshChunkOffset = (data_array[2][1][count][1].fileOffset_vertexPos + data_array[1][count].fileOffset_subMeshDescr)
		
		------------------------------------------
		fseek bs meshChunkOffset #seek_set --jump to meshChunk
		------------------------------------------
			
		format "******************************* READING THE MASTER MESH: %\n" (ftell bs)
		
		--------------------------------------------------------------
		type5_DECALS_VFX_posReader \
													bs \
													nVerts \																			
													data_array \
													header_info \
													faceChunkOffset \
													numFaces \
													str_2Fill
		--------------------------------------------------------------
		
		masterRead = true
	)
	
	--prepare containers in the arrays
-- 	Append data_array[2][2] #()
-- 	Append data_array[4][2] #()		
-- 	Append data_array[3][2] #()
	
	
	if (data_array[1][count]._prefix > 1) then --children to master mesh
	(	
		Append data_array[2][2] #()--!!??
		Append data_array[4][2] #()--!!??
		
		Append data_array[3][2] #()
		
		--------------------------------------------------------------
		 --children to master mesh (we subract 1 because 1 is the Master Mesh that we have already read above)
		for sx=1 to data_array[1][count]._prefix-1 do
		--for sx=1 to 2 do --temp
		(
			---------------------Seek the right fileoffset position to the submesh description---------------------
			if sx > 1 then
			(
				nextChunk = data_array[2][2][count][sx-1].fileoffset_next_subChunk + data_array[2][2][count][sx-1].fileOffset_subMeshDescr
				fseek bs nextChunk #seek_set
			)
			else if sx == 1 then
			(
				nextChunk = (data_array[2][1][count][1].fileoffset_next_subChunk + data_array[1][count].fileOffset_subMeshDescr)
				fseek bs nextChunk #seek_set
			)
			----------------------------------------------------------------------------------------------------------------
			
			fill_SUB_subMeshDescription \
													bs \
													header_info \
													count \
													data_array				
		)
		--------------------------------------------------------------		
		
		format "Count----: %\n" count
		

		for sx=1 to data_array[2][2][count].count do
		(
			next_subChunk				= data_array[2][2][count][sx].fileoffset_next_subChunk 
			fileOffset_vertPos			= data_array[2][2][count][sx].fileOffset_vertexPos
			cur_pos							= data_array[2][2][count][sx].fileOffset_subMeshDescr			
			nVerts 							= data_array[2][2][count][sx].numverts	
			faceChunkOffset				= (data_array[2][2][count][sx].fileOffset_faceIndices + cur_pos)
			numFaces						= data_array[2][2][count][sx].halfNumFaceIndices						

			fseek bs (fileOffset_vertPos+cur_pos) #seek_set		
						
			str_2Fill_2 = geomChunk()
				
				
						
	--	 	for px =1 to 10 do
	--	 	(
	--	 		prefix = readlong bs
	-- 			Append str_2Fill_2.subSubM_Prefix_arr prefix
	-- 		)						
				
			--REPORT		
-- 				format "count: %\n" count
-- 			format "*******will begin to read pos chunk here: %\n" (ftell bs)
-- 			format "___next_subChunk___: %\n" next_subChunk
-- 			format "___fileOffset_vertPos___: %\n" fileOffset_vertPos
-- 			format "___cur_pos___: %\n" cur_pos
-- 			format "___nVerts___: %\n" nVerts
-- 			format "___faceChunkOffset___: %\n" faceChunkOffset
-- 			format "___numFaces___: %\n\n" numFaces
						
						
			format "(ftell bs): %\n" (ftell bs)		
			--------------------------------------------------------------		
			type5_DECALS_VFX_posReader \
														bs \
														nVerts \																											
														data_array \
														header_info \														
														faceChunkOffset \
														numFaces \
														str_2Fill_2
			--------------------------------------------------------------				
				
			Append data_array[3][2][count] str_2Fill_2				
		)
	)	
	masterRead = false
)
-------------------------



-- /// TYPE 5
--NO UVs, --!!?? -uncommon only - 16 bytes per pos element - 3 * float for x, y, z (12 bytes) - and 4 unknown bytes
-------------------------
fn type6_DECALS_VFX_posReader \
												bs \
												nVerts \																					
												data_array \											
												header_info \											
												faceChunkOffset \
												numFaces \
												str_2Fill =
(
	--for i=1 to data_array[2][count][sx].numverts do
	for i=1 to nVerts do
	(
		--vertex	
		x = readfloat bs
		y = readfloat bs	
		z = readfloat bs
		
			u1 = readfloat bs
		
		Append str_2Fill.verts [x,y,z]
		--Append str_2Fill.uvw [u,(1-v),w*0] --fill uvw array
	)			

	fseek bs faceChunkOffset #seek_set --jump to meshChunk		
		
	--The entire faces chunk	
	for i=1 to (numFaces/3) do
	(
		a = (readshort bs)
		b = (readshort bs)
		c = (readshort bs)
					
		Append str_2Fill.faces [a+1,b+1,c+1]
	)		
)
--This are rigged and anim meshes for Cinematic variantmodels -this function handles 32 bytes per element
fn type6_DECALS_VFX_meshParse \
												bs \
												nVerts \
												count \										
												data_array \
												header_info \
												str_2Fill =
(	
	if masterRead == false then
	(
		--These two will be used in the pos reader
		faceChunkOffset = data_array[2][1][count][1].fileOffset_faceIndices + data_array[1][count].fileOffset_subMeshDescr		
		numFaces = data_array[2][1][count][1].halfNumFaceIndices
		
		
		meshChunkOffset = (data_array[2][1][count][1].fileOffset_vertexPos + data_array[1][count].fileOffset_subMeshDescr)
		
		------------------------------------------
		fseek bs meshChunkOffset #seek_set --jump to meshChunk
		------------------------------------------
			
		format "******************************* READING THE MASTER MESH: %\n" (ftell bs)
		
		--------------------------------------------------------------
		type6_DECALS_VFX_posReader \
													bs \
													nVerts \																			
													data_array \
													header_info \
													faceChunkOffset \
													numFaces \
													str_2Fill
		--------------------------------------------------------------
		
		masterRead = true
	)
	
	--prepare containers in the arrays
-- 	Append data_array[2][2] #()
-- 	Append data_array[4][2] #()		
-- 	Append data_array[3][2] #()
	
	
	if (data_array[1][count]._prefix > 1) then --children to master mesh
	(	
		Append data_array[2][2] #()--!!??
		Append data_array[4][2] #()--!!??
		
		Append data_array[3][2] #()
		
		--------------------------------------------------------------
		 --children to master mesh (we subract 1 because 1 is the Master Mesh that we have already read above)
		for sx=1 to data_array[1][count]._prefix-1 do
		--for sx=1 to 2 do --temp
		(
			---------------------Seek the right fileoffset position to the submesh description---------------------
			if sx > 1 then
			(
				nextChunk = data_array[2][2][count][sx-1].fileoffset_next_subChunk + data_array[2][2][count][sx-1].fileOffset_subMeshDescr
				fseek bs nextChunk #seek_set
			)
			else if sx == 1 then
			(
				nextChunk = (data_array[2][1][count][1].fileoffset_next_subChunk + data_array[1][count].fileOffset_subMeshDescr)
				fseek bs nextChunk #seek_set
			)
			----------------------------------------------------------------------------------------------------------------
			
			fill_SUB_subMeshDescription \
													bs \
													header_info \
													count \
													data_array				
		)
		--------------------------------------------------------------		
		
		format "Count----: %\n" count
		

		for sx=1 to data_array[2][2][count].count do
		(
			next_subChunk				= data_array[2][2][count][sx].fileoffset_next_subChunk 
			fileOffset_vertPos			= data_array[2][2][count][sx].fileOffset_vertexPos
			cur_pos							= data_array[2][2][count][sx].fileOffset_subMeshDescr			
			nVerts 							= data_array[2][2][count][sx].numverts	
			faceChunkOffset				= (data_array[2][2][count][sx].fileOffset_faceIndices + cur_pos)
			numFaces						= data_array[2][2][count][sx].halfNumFaceIndices						

			fseek bs (fileOffset_vertPos+cur_pos) #seek_set		
						
			str_2Fill_2 = geomChunk()
				
				
						
	--	 	for px =1 to 10 do
	--	 	(
	--	 		prefix = readlong bs
	-- 			Append str_2Fill_2.subSubM_Prefix_arr prefix
	-- 		)						
				
			--REPORT		
-- 				format "count: %\n" count
-- 			format "*******will begin to read pos chunk here: %\n" (ftell bs)
-- 			format "___next_subChunk___: %\n" next_subChunk
-- 			format "___fileOffset_vertPos___: %\n" fileOffset_vertPos
-- 			format "___cur_pos___: %\n" cur_pos
-- 			format "___nVerts___: %\n" nVerts
-- 			format "___faceChunkOffset___: %\n" faceChunkOffset
-- 			format "___numFaces___: %\n\n" numFaces
						
						
			format "(ftell bs): %\n" (ftell bs)		
			--------------------------------------------------------------		
			type6_DECALS_VFX_posReader \
														bs \
														nVerts \																											
														data_array \
														header_info \														
														faceChunkOffset \
														numFaces \
														str_2Fill_2
			--------------------------------------------------------------				
				
			Append data_array[3][2][count] str_2Fill_2				
		)
	)	
	masterRead = false
)
-------------------------
--///////////////////////////////////////////////End of TYPE 5 /////////////////////////////////////////////////



--//////////////////////////////////////////////////// TYPE 6 ////////////////////////////////////////////////////
--///////////////////////////////////// rigidmodels /////////////////////////////////////
--each meshChunk element is 32 bytes --siege tower for example --rigid models, no weights, no skeleton
-------------------------
fn type6_44_posReader \
									bs \
									nVerts \																					
									data_array \											
									header_info \											
									faceChunkOffset \
									numFaces \
									str_2Fill =
(
	--for i=1 to data_array[2][count][sx].numverts do
	for i=1 to nVerts do
	(				
		--vertex
		x = readHalfFloat bs
		y = readHalfFloat bs	
		z = readHalfFloat bs
				
		--unknown
		u2 = readHalfFloat bs
				
		--UVs		
		u = readHalfFloat bs	
		v = readHalfFloat bs
		w = readHalfFloat bs	
			
		--unknown
		u3 = readHalfFloat bs
		u4 = readHalfFloat bs
		u5 = readHalfFloat bs
		u6 = readHalfFloat bs
		u7 = readHalfFloat bs
		u8 = readHalfFloat bs				
		u9 = readshort bs
		u10 = readshort bs
		
		--unknown
		u1 = readHalfFloat bs
		
		Append str_2Fill.verts [x,y,z] --fill vert array
		Append str_2Fill.uvw [u,(1-v),w*0] --fill uvw array
	)			

	fseek bs faceChunkOffset #seek_set --jump to meshChunk		
		
	--The entire faces chunk	
	for i=1 to (numFaces/3) do
	(
		a = (readshort bs)
		b = (readshort bs)
		c = (readshort bs)
					
		Append str_2Fill.faces [a+1,b+1,c+1]
	)		
)
--This are rigged and anim meshes for Cinematic variantmodels -this function handles 32 bytes per element
fn type6_44_meshParse \
									bs \
									nVerts \
									count \										
									data_array \
									header_info \
									str_2Fill =
(	
	if masterRead == false then
	(
		--These two will be used in the pos reader
		faceChunkOffset = data_array[2][1][count][1].fileOffset_faceIndices + data_array[1][count].fileOffset_subMeshDescr		
		numFaces = data_array[2][1][count][1].halfNumFaceIndices
		
		
		meshChunkOffset = (data_array[2][1][count][1].fileOffset_vertexPos + data_array[1][count].fileOffset_subMeshDescr)
		
		------------------------------------------
		fseek bs meshChunkOffset #seek_set --jump to meshChunk
		------------------------------------------
			
		format "******************************* READING THE MASTER MESH: %\n" (ftell bs)
		
		--------------------------------------------------------------
		type6_44_posReader \
										bs \
										nVerts \																			
										data_array \
										header_info \
										faceChunkOffset \
										numFaces \
										str_2Fill
		--------------------------------------------------------------
		
		masterRead = true
	)
	
	--prepare containers in the arrays
-- 	Append data_array[2][2] #()
-- 	Append data_array[4][2] #()		
-- 	Append data_array[3][2] #()
	
	
	if (data_array[1][count]._prefix > 1) then --children to master mesh
	(	
		Append data_array[2][2] #()--!!??
		Append data_array[4][2] #()--!!??
		
		Append data_array[3][2] #()
		
		--------------------------------------------------------------
		 --children to master mesh (we subract 1 because 1 is the Master Mesh that we have already read above)
		for sx=1 to data_array[1][count]._prefix-1 do
		--for sx=1 to 2 do --temp
		(
			---------------------Seek the right fileoffset position to the submesh description---------------------
			if sx > 1 then
			(
				nextChunk = data_array[2][2][count][sx-1].fileoffset_next_subChunk + data_array[2][2][count][sx-1].fileOffset_subMeshDescr
				fseek bs nextChunk #seek_set
			)
			else if sx == 1 then
			(
				nextChunk = (data_array[2][1][count][1].fileoffset_next_subChunk + data_array[1][count].fileOffset_subMeshDescr)
				fseek bs nextChunk #seek_set
			)
			----------------------------------------------------------------------------------------------------------------
			
			fill_SUB_subMeshDescription \
													bs \
													header_info \
													count \
													data_array				
		)
		--------------------------------------------------------------		
		
		format "Count----: %\n" count
		

		for sx=1 to data_array[2][2][count].count do
		(
			next_subChunk				= data_array[2][2][count][sx].fileoffset_next_subChunk 
			fileOffset_vertPos			= data_array[2][2][count][sx].fileOffset_vertexPos
			cur_pos							= data_array[2][2][count][sx].fileOffset_subMeshDescr			
			nVerts 							= data_array[2][2][count][sx].numverts	
			faceChunkOffset				= (data_array[2][2][count][sx].fileOffset_faceIndices + cur_pos)
			numFaces						= data_array[2][2][count][sx].halfNumFaceIndices						

			fseek bs (fileOffset_vertPos+cur_pos) #seek_set		
						
			str_2Fill_2 = geomChunk()
				
				
						
	--	 	for px =1 to 10 do
	--	 	(
	--	 		prefix = readlong bs
	-- 			Append str_2Fill_2.subSubM_Prefix_arr prefix
	-- 		)						
				
			--REPORT		
-- 				format "count: %\n" count
-- 			format "*******will begin to read pos chunk here: %\n" (ftell bs)
-- 			format "___next_subChunk___: %\n" next_subChunk
-- 			format "___fileOffset_vertPos___: %\n" fileOffset_vertPos
-- 			format "___cur_pos___: %\n" cur_pos
-- 			format "___nVerts___: %\n" nVerts
-- 			format "___faceChunkOffset___: %\n" faceChunkOffset
-- 			format "___numFaces___: %\n\n" numFaces
						
						
			format "(ftell bs): %\n" (ftell bs)		
			--------------------------------------------------------------		
			type6_44_posReader \
											bs \
											nVerts \																											
											data_array \
											header_info \														
											faceChunkOffset \
											numFaces \
											str_2Fill_2
			--------------------------------------------------------------				
				
			Append data_array[3][2][count] str_2Fill_2				
		)
	)	
	masterRead = false
)
-------------------------

--///////////////////////////////////// _variantmodels /////////////////////////////////////
--For WEIGHTS and SKELETON RIGGED meshes (variantmeshes)
--each meshChunk element is 32 bytes --used for CINE models
-- (each bone has exclusive dedicated weight info here 4 bytes (1bone, 2.bone, weight4bone1/255, weight4bone2/255) instead of ordinary 3 (bone1, bone2 then one weight calculated for both)
----------------------------------------------------
fn type6_CINE_posReader \
									bs \
									nVerts \																					
									data_array \											
									header_info \											
									faceChunkOffset \
									numFaces \
									str_2Fill =
(
	--for i=1 to data_array[2][count][sx].numverts do
	for i=1 to nVerts do
	(
		str_weights = weights()
		
		---------- verts ----------
		x = readHalfFloat bs
		y = readHalfFloat bs
		z = readHalfFloat bs		
				readshort bs --padding		
		
		--Bone Weights
		str_weights = weights()	
			str_weights.bone1 = readbyte bs
			str_weights.bone2 = readbyte bs
				pad = readshort bs --padding
			str_weights.weightA = readbyte bs #unsigned
			str_weights.weightB = readbyte bs #unsigned		
				str_weights.weight1 = str_weights.weightA/255.0
				str_weights.weight2 = str_weights.weightB/255.0
			Append str_2Fill.weights_arr str_weights		
				for x=1 to 3 do
				(
					pad = readshort bs
					--Append paddings_arr pad
				)
				

		---------- UVs ----------
		u = readhalffloat bs
		v = readhalffloat bs				
				for x=1 to 4 do (readshort bs) --padding				


		--Append verts [x,z,y]
		Append str_2Fill.verts [x,y,z]			
		-- 	Append normals [ny,nz,nx]
		Append str_2Fill.uvw [u,(1-v),0] --we flip the UVs vertically
		--Append unknown2 [e1,e2,e3,e4]
	)			

	fseek bs faceChunkOffset #seek_set --jump to meshChunk		
		
	--The entire faces chunk	
	for i=1 to (numFaces/3) do
	(
		a = (readshort bs)
		b = (readshort bs)
		c = (readshort bs)
					
		Append str_2Fill.faces [a+1,b+1,c+1]
	)		
)
--This are rigged and anim meshes for Cinematic variantmodels -this function handles 32 bytes per element
fn type6_CINE_meshParse \
									bs \
									nVerts \
									count \										
									data_array \
									header_info \
									str_2Fill =
(	
	if masterRead == false then
	(
		--These two will be used in the pos reader
		faceChunkOffset = data_array[2][1][count][1].fileOffset_faceIndices + data_array[1][count].fileOffset_subMeshDescr		
		numFaces = data_array[2][1][count][1].halfNumFaceIndices
		
		
		meshChunkOffset = (data_array[2][1][count][1].fileOffset_vertexPos + data_array[1][count].fileOffset_subMeshDescr)
		
		------------------------------------------
		fseek bs meshChunkOffset #seek_set --jump to meshChunk
		------------------------------------------
			
		format "******************************* READING THE MASTER MESH: %\n" (ftell bs)
		
		--------------------------------------------------------------
		type6_CINE_posReader \
										bs \
										nVerts \																			
										data_array \
										header_info \
										faceChunkOffset \
										numFaces \
										str_2Fill
		--------------------------------------------------------------
		
		masterRead = true
	)
	
	--prepare containers in the arrays
-- 	Append data_array[2][2] #()
-- 	Append data_array[4][2] #()		
-- 	Append data_array[3][2] #()
	
	
	if (data_array[1][count]._prefix > 1) then --children to master mesh
	(	
		Append data_array[2][2] #()--!!??
		Append data_array[4][2] #()--!!??
		
		Append data_array[3][2] #()
		
		--------------------------------------------------------------
		 --children to master mesh (we subract 1 because 1 is the Master Mesh that we have already read above)
		for sx=1 to data_array[1][count]._prefix-1 do
		--for sx=1 to 2 do --temp
		(
			---------------------Seek the right fileoffset position to the submesh description---------------------
			if sx > 1 then
			(
				nextChunk = data_array[2][2][count][sx-1].fileoffset_next_subChunk + data_array[2][2][count][sx-1].fileOffset_subMeshDescr
				fseek bs nextChunk #seek_set
			)
			else if sx == 1 then
			(
				nextChunk = (data_array[2][1][count][1].fileoffset_next_subChunk + data_array[1][count].fileOffset_subMeshDescr)
				fseek bs nextChunk #seek_set
			)
			----------------------------------------------------------------------------------------------------------------
			
			fill_SUB_subMeshDescription \
													bs \
													header_info \
													count \
													data_array				
		)
		--------------------------------------------------------------		
		
		format "Count----: %\n" count
		

		for sx=1 to data_array[2][2][count].count do
		(
			next_subChunk				= data_array[2][2][count][sx].fileoffset_next_subChunk 
			fileOffset_vertPos			= data_array[2][2][count][sx].fileOffset_vertexPos
			cur_pos							= data_array[2][2][count][sx].fileOffset_subMeshDescr			
			nVerts 							= data_array[2][2][count][sx].numverts	
			faceChunkOffset				= (data_array[2][2][count][sx].fileOffset_faceIndices + cur_pos)
			numFaces						= data_array[2][2][count][sx].halfNumFaceIndices						

			fseek bs (fileOffset_vertPos+cur_pos) #seek_set		
						
			str_2Fill_2 = geomChunk()
				
				
						
	--	 	for px =1 to 10 do
	--	 	(
	--	 		prefix = readlong bs
	-- 			Append str_2Fill_2.subSubM_Prefix_arr prefix
	-- 		)						
				
			--REPORT		
-- 				format "count: %\n" count
-- 			format "*******will begin to read pos chunk here: %\n" (ftell bs)
-- 			format "___next_subChunk___: %\n" next_subChunk
-- 			format "___fileOffset_vertPos___: %\n" fileOffset_vertPos
-- 			format "___cur_pos___: %\n" cur_pos
-- 			format "___nVerts___: %\n" nVerts
-- 			format "___faceChunkOffset___: %\n" faceChunkOffset
-- 			format "___numFaces___: %\n\n" numFaces
						
						
			format "(ftell bs): %\n" (ftell bs)		
			--------------------------------------------------------------		
			type6_CINE_posReader \
											bs \
											nVerts \																											
											data_array \
											header_info \														
											faceChunkOffset \
											numFaces \
											str_2Fill_2
			--------------------------------------------------------------				
				
			Append data_array[3][2][count] str_2Fill_2				
		)
	)	
	masterRead = false
)
----------------------------------------------------


----------------------------------------------------
fn type6_GAME_posReader  \
										bs \
										nVerts \																					
										data_array \											
										header_info \											
										faceChunkOffset \
										numFaces \
										str_2Fill =
(
	--for i=1 to data_array[2][count][sx].numverts do
	for i=1 to nVerts do
	(
		str_weights					= weights()
					
		x								= (readHalfFloat bs)
		y								= (readHalfFloat bs)
		z								= (readHalfFloat bs)
			u1							= readbyte bs
			u2							= readbyte bs
						
		--Bone Weights
		str_weights.bone1		= readbyte bs
		str_weights.bone2		= readbyte bs
		str_weights.weight		= readbyte bs #unsigned
		str_weights.weight1		= str_weights.weight/255.0
		str_weights.weight2		= (255.0-str_weights.weight)/255.0
			Append str_2Fill.weights_arr str_weights
						
		readbyte bs --jump
		readfloat bs --jump
						
		u								= (readHalfFloat bs)
		v								= (readHalfFloat bs)
						
		ux								= (readHalfFloat bs)
		uy								= (readHalfFloat bs)
		uz								= (readHalfFloat bs)
						
		readshort bs --jump
						
		--Append verts [x,z,y]
		Append str_2Fill.verts [x,y,z]
			Append str_2Fill.unknown [ux,uy,uz]
		-- 	Append normals [ny,nz,nx]
		Append str_2Fill.uvw [u,(1-v),0] --we flip the UVs vertically
		--Append unknown2 [e1,e2,e3,e4]
	)			

	fseek bs faceChunkOffset #seek_set --jump to meshChunk		
		
	--The entire faces chunk	
	for i=1 to (numFaces/3) do
	(
		a = (readshort bs)
		b = (readshort bs)
		c = (readshort bs)
					
		Append str_2Fill.faces [a+1,b+1,c+1]
	)		
)

--This are rigged and anim meshes for characters -this function handles 28 bytes per element
fn type6_GAME_meshParse  \
										bs \
										nVerts \
										count \										
										data_array \
										header_info \
										str_2Fill =
(
	if masterRead == false then
	(
		--These two will be used in the pos reader
		faceChunkOffset = data_array[2][1][count][1].fileOffset_faceIndices + data_array[1][count].fileOffset_subMeshDescr		
		numFaces = data_array[2][1][count][1].halfNumFaceIndices
		
		
		meshChunkOffset = (data_array[2][1][count][1].fileOffset_vertexPos + data_array[1][count].fileOffset_subMeshDescr)
		
		------------------------------------------
		fseek bs meshChunkOffset #seek_set --jump to meshChunk
		------------------------------------------
			
		format "******************************* READING THE MASTER MESH: %\n" (ftell bs)
		
		--------------------------------------------------------------
		type6_GAME_posReader  \
											bs \
											nVerts \																				
											data_array \
											header_info \
											faceChunkOffset \
											numFaces \
											str_2Fill
		--------------------------------------------------------------
		
		masterRead = true
	)
	
	--prepare containers in the arrays
-- 	Append data_array[2][2] #()
-- 	Append data_array[4][2] #()
-- 	Append data_array[3][2] #()
	
	
	if data_array[1][count]._prefix > 1 then --children to master mesh
	(
		Append data_array[2][2] #()--!!??
		Append data_array[4][2] #()--!!??
		
		Append data_array[3][2] #()
		
		--------------------------------------------------------------
		for sx=1 to data_array[1][count]._prefix-1 do --children to master mesh
		(
			---------------------Seek the right fileoffset position to the submesh description---------------------
			if sx > 1 then
			(
				nextChunk = data_array[2][2][count][sx-1].fileoffset_next_subChunk + data_array[2][2][count][sx-1].fileOffset_subMeshDescr
				fseek bs nextChunk #seek_set
			)
			else if sx == 1 then
			(
				nextChunk = (data_array[2][1][count][1].fileoffset_next_subChunk + data_array[1][count].fileOffset_subMeshDescr)
				fseek bs nextChunk #seek_set
			)
			----------------------------------------------------------------------------------------------------------------
			
			fill_SUB_subMeshDescription \
													bs \
													header_info \
													count \
													data_array
		)
		--------------------------------------------------------------		
		
		for sx=1 to data_array[2][2][count].count do
		(
			next_subChunk				= data_array[2][2][count][sx].fileoffset_next_subChunk 
			fileOffset_vertPos			= data_array[2][2][count][sx].fileOffset_vertexPos
			cur_pos							= data_array[2][2][count][sx].fileOffset_subMeshDescr			
			nVerts 							= data_array[2][2][count][sx].numverts	
			faceChunkOffset				= (data_array[2][2][count][sx].fileOffset_faceIndices + cur_pos)
			numFaces						= data_array[2][2][count][sx].halfNumFaceIndices						

			fseek bs (fileOffset_vertPos+cur_pos) #seek_set		
						
			str_2Fill_2 = geomChunk()
				
				
						
	--	 	for px =1 to 10 do
	--	 	(
	--	 		prefix = readlong bs
	-- 			Append str_2Fill_2.subSubM_Prefix_arr prefix
	-- 		)						
				
			--REPORT		
-- 				format "count: %\n" count
-- 			format "*******will begin to read pos chunk here: %\n" (ftell bs)
-- 			format "___next_subChunk___: %\n" next_subChunk
-- 			format "___fileOffset_vertPos___: %\n" fileOffset_vertPos	
-- 			format "___cur_pos___: %\n" cur_pos
-- 			format "___nVerts___: %\n" nVerts
-- 			format "___faceChunkOffset___: %\n" faceChunkOffset
-- 			format "___numFaces___: %\n\n" numFaces
						
			--------------------------------------------------------------		
			type6_GAME_posReader \
												bs \
												nVerts \																											
												data_array \
												header_info \														
												faceChunkOffset \
												numFaces \
												str_2Fill_2
			--------------------------------------------------------------
				
			Append data_array[3][2][count] str_2Fill_2
		)				
	)	
	masterRead = false
)
----------------------------------------------------
--///////////////////////////////////////////////End of TYPE 6 /////////////////////////////////////////////////
--///////////////////////////////////////////////END OF MESH PARSING FUNCTIONS ////////////////////////////////////////////////



fn fill_geomChunk \
							bstream \
							headerInfo \
							data_array =
(	
	--for x=1 to data_array[2][1].count do --num Master Meshes
	for x=1 to headerInfo.numMeshes do --num Master Meshes
	(
		str_2Fill = geomChunk() --create struct instance			
			
		-- ///////////////////////////// Read the Mesh Chunks /////////////////////////////
		if (headerInfo.fileType == 0x00000006) then
		(					
			numVerts = data_array[2][1][x][1].numverts
					
			if (data_array[2][1][x][1].meshChunk_type != 0x00000043) then --if this is NOT!!! DECAL / VFX
			(			
				if data_array[2][1][x][1].prefix_GAME3_CINE4_RIGID0 == 0x0004 then --prefix_GAME3_CINE4_RIGID0
				(
					--32 bytes --used for CINE models
					type6_CINE_meshParse \
													bstream \
													numVerts \
													x \
													data_array \
													headerInfo \
													str_2Fill
				)
				else if data_array[2][1][x][1].prefix_GAME3_CINE4_RIGID0 == 0x0003 then --prefix_GAME3_CINE4_RIGID0
				(					
					--28 bytes
					type6_GAME_meshParse \
														bstream \
														numVerts \
														x \
														data_array \
														headerInfo \
														str_2Fill
				)
				else if data_array[2][1][x][1].prefix_GAME3_CINE4_RIGID0 == 0x0000 then --prefix_GAME3_CINE4_RIGID0 (no weights, no skeleton)
				(
					--32 bytes --siege tower for example
					type6_44_meshParse \
													bstream \
													numVerts \
													x \
													data_array \
													headerInfo \
													str_2Fill
				)
			)
			else  --Only DECALS / VFX
			(
				--DECALS/VFX items (tiny meshes, not game models and of little to no interest to me)
				--\\diskstation4\Game_Models\Games\TotalWar_Rome_2\extract\Total War Rome II\data\rigidmodels\decals\battle
				--NO UVs, --!!?? -uncommon only - 16 bytes per pos element - 3 * float for x, y, z (12 bytes) - and 4 unknown bytes
				type6_DECALS_VFX_meshParse \
															bstream \
															numVerts \
															x \
															data_array \
															headerInfo \
															str_2Fill
			)
		)
		else if (headerInfo.fileType == 0x00000005) then
		(
			numVerts = data_array[2][1][x][1].numverts
					
			if (data_array[2][1][x][1].meshChunk_type != 0x00000043) then
			(				
				if data_array[2][1][x][1].prefix_GAME3_CINE4_RIGID0 == 0x0000 then
				(
					--32 bytes
					type5_44_meshParse \
													bstream \
													numVerts \
													x \
													data_array \
													headerInfo \
													str_2Fill
				)
				else if data_array[2][1][x][1].prefix_GAME3_CINE4_RIGID0 == 0x0003 then --prefix_GAME3_CINE4_RIGID0
				(
					--28 bytes
					type6_GAME_meshParse  \
														bstream \
														numVerts \
														x \
														data_array \
														headerInfo \
														str_2Fill
				)	
			)
			else --Only DECALS / VFX
			(
				--DECALS/VFX items (tiny meshes, not game models and of little to no interest to me)
				--\\diskstation4\Game_Models\Games\TotalWar_Rome_2\extract\Total War Rome II\data\rigidmodels\decals\battle
				--NO UVs, --!!?? -uncommon only - 16 bytes per pos element - 3 * float for x, y, z (12 bytes) - and 4 unknown bytes
				type5_DECALS_VFX_meshParse \
															bstream \
															numVerts \
															x \
															data_array \
															headerInfo \
															str_2Fill
			)			
		)
		Append data_array[3][1] #()
		Append data_array[3][1][x] str_2Fill
		-- //////////////////////////// End of reading the Mesh Chunks ////////////////////////////	
	)
)
--------------------------------'''''''''''''''''''''''''''''''''''''''''''''''''''''

--Hide the higher lods
fn lods_to_layerHidden obj = (	

	if (
			(matchPattern obj.name pattern:"*lod*2*" ignoreCase:false) OR \
			(matchPattern obj.name pattern:"*lod*3*" ignoreCase:false) OR \
			(matchPattern obj.name pattern:"*lod*4*" ignoreCase:false) OR \
			(matchPattern obj.name pattern:"*lod*5*" ignoreCase:false) OR \
			(matchPattern obj.name pattern:"*lod*6*" ignoreCase:false) \
		) \
		AND \
		( \
			(matchPattern obj.name pattern:"*lod1*" ignoreCase:false) != true OR \
			(matchPattern obj.name pattern:"*lod01*" ignoreCase:false) != true \
		) \
		then
		(
			LayerManager.newLayerFromName "Lods"
			lodLayer = LayerManager.getLayerFromName "Lods"
			lodLayer.addNode obj
			if NOT lodLayer.ishidden then
			(
				lodLayer.ishidden = true
			)
		)
)

fn have_Skeleton_check_rootData =
(
	for dx=1 to rootData[2].count do
	(
		val = rootData[2][dx][6][1].skeleton_type -- the header is [6] in the data_array

		for dx2=1 to rootData[2][dx][2][1].count do
		(			
			val_type 	= rootData[2][dx][2][1][dx2][1].meshChunk_type
					
			if val != undefined AND val != "" then
			(
				case of
				(
					(val_type == 0x00000041) : (return true)
					(val_type == 0x00000046) : (return true)
					(val_type == 0x00000052) : (return true)
					(val_type == 0x0000004F) : (return true)
					default : return false;
				)					
			)
			else
			(
				return false;
			)
		)
	)
	
	return true;
)
	

--Checks if the master mesh or submesh has a skeleton, via the data_array[2][x]... struct subMeshDescription.meshChunk_type
fn have_Skeleton_check \
									master \ --bool, true if this is the masterMesh (if true, then n2 can be any value)
									n1 \ --master mesh index
									n2 \ --submesh index
									data =
(
	if (str_header.skeleton_type != undefined) AND \
		(str_header.skeleton_type != "") then
	(
		val = false
		
		if master == true then
		(
			val = data[2][1][n1][1].meshChunk_type
		)
		else
		(
			val = data[2][2][n1][n2].meshChunk_type
		)
		
		if val != undefined then
		(
			case of
			(
				(val == 0x00000041) : (return true)
				(val == 0x00000046) : (return true)
				(val == 0x00000052) : (return true)
				(val == 0x0000004F) : (return true) --greaves, helmets
			)
		)
	)
	else
	(
		return false;
	)
)

fn meshBuilderSub \
							data_array \
							info =
(
	for m=1 to data_array[3][2].count do
	(		
		Append mesh2_rig_animate_arr[2]	#()-------------------
		Append meshes_to_texture[2]		#()-------------------

		_nodesS_arr = #()
		
		for m2=1 to data_array[3][2][m].count do
		(
			--/*	
			msh = mesh vertices:data_array[3][2][m][m2].verts faces:data_array[3][2][m][m2].faces
			
			if msh != undefined then
			(	
				--array map to bounding box
				--rootData[2][i]	[2][1][[1]][1].boundingBox_2verts --mastermesh
				--rootData[2][i]	[2][2][n][1].boundingBox_2verts --mastermesh			
				
				temp_arr = #(#(),#(),#(),#())					
					Append temp_arr[1] m
					Append temp_arr[2] msh
					Append temp_arr[3] str_header.meshFilePath
					Append temp_arr[4] data_array[2][2][m][m2].boundingBox_2verts
				Append MESH_NODES_4_attachPoints_arr temp_arr
					
				Append		_nodesS_arr		msh
				
				skelCheck = have_Skeleton_check \
																false \
																m \
																m2 \
																data_array
				
				if skelCheck == true then
				(
					Append mesh2_rig_animate_arr[2][m] msh-------------------
				)
					
						
				if iskindof msh Editable_mesh then
				(						
					nVerts = data_array[2][2][m][m2].numVerts
		-- 			nverts = (getnumverts msh)
						
					if nVerts > 0 then
					(
						-- if the mesh has UVs, else skip them
						if NOT noUVs then
						(
							--------------UVs--------------
							setNumTVerts msh nverts
							buildTVFaces msh
							for vx=1 to nVerts do setTVert msh vx data_array[3][2][m][m2].uvw[vx]
							for vx=1 to data_array[3][2][m][m2].faces.count do setTVFace msh vx data_array[3][2][m][m2].faces[vx]
							---------------------------------
						)
						else
						(
							format "The mesh does not have any UVs!\n"
						)
								
						if data_array[2][2][m][m2].groupName != undefined then
						(
							msh.name = data_array[2][2][m][m2].groupName
									
							--lods_to_layerHidden msh
						)							
							
						Append meshes_to_texture[2][m] msh --store this mesh to use for texturing later-------------------
					)
					else
					(
						if data_array[2][2][m][m2].groupName != undefined then
						(
							msh.name = data_array[2][2][m][m2].groupName
						)
								
						format "The mesh ( % ) has zero vertices, cannot build mesh.\n" msh.name
						format "It is possible that there are vertices that the importer failed to find/parse.\n"
					)
				)
				
			)				
			else
			(
				Messagebox "For some reason, we could not build mesh!"
			)			
			--*/
		)
		
		Append		data_array[9][data_array[9].count][2]		_nodesS_arr
	)
)

fn meshBuilder \
					data_array \
					info =
(
	mesh2_rig_animate_arr		= #(#(),#())	
	meshes_to_texture			= #(#(),#())	
	
	_nodesM_arr	= #(#(),#())
	
	for m=1 to data_array[3][1].count do
	(
		Append		mesh2_rig_animate_arr[1]		#()
		Append		meshes_to_texture[1]			#()
		
		msh = mesh vertices:data_array[3][1][m][1].verts faces:data_array[3][1][m][1].faces
			
		if msh != undefined then
		(					
			--array map to bounding box
			--rootData[2][i]	[2][1][[1]][1].boundingBox_2verts --mastermesh
			--rootData[2][i]	[2][2][n][1].boundingBox_2verts --mastermesh
			
			temp_arr	= #(#(),#(),#(),#())			
				
				Append temp_arr[1] m
				Append temp_arr[2] msh
				Append temp_arr[3] str_header.meshFilePath
				Append temp_arr[4] data_array[2][1][m][1].boundingBox_2verts
			Append MESH_NODES_4_attachPoints_arr temp_arr
			
			--#()  \ -- [9][1] Mesh Nodes	[9][n][1] = masterMesh Node		[9][n][2] = The submesh Nodes belonging to the masterMesh	
			--Append nodes to array that we will add to the data_array (the data_array will then later be stored in the rootData array)


			Append		_nodesM_arr[1]	msh --This is expected (and it should) always only add one (there is only one masterMesh)

			
			skelCheck = have_Skeleton_check \
															true \
															m \
															1 \
															data_array
				
			if skelCheck == true then
			(				
				Append mesh2_rig_animate_arr[1][m] msh------------------------
			)
				
			if iskindof msh Editable_mesh then
			(
				--nverts = (getnumverts msh)
				nVerts = data_array[2][1][m][1].numVerts
					
				if nVerts > 0 then
				(
					-- if the mesh has UVs, else skip them
					if NOT noUVs then
					(
						--------------UVs--------------
						setNumTVerts msh nverts
						buildTVFaces msh
						for vx=1 to nVerts do setTVert msh vx data_array[3][1][m][1].uvw[vx]
						for vx=1 to data_array[3][1][m][1].faces.count do setTVFace msh vx data_array[3][1][m][1].faces[vx]
						---------------------------------
					)
					else
					(
						format "The mesh does not have any UVs!\n"
					)
						
					if data_array[2][1][m][1].groupName != undefined then
					(
						msh.name = data_array[2][1][m][1].groupName
							
						--lods_to_layerHidden msh
					)
						
					Append meshes_to_texture[1][m] msh --store this mesh to use for texturing later------------------------
				)
				else
				(
					if data_array[2][1][m][1].groupName != undefined then
					(
						msh.name = data_array[2][1][m][1].groupName
					)
						
					format "The mesh ( % ) has zero vertices, cannot build mesh.\n" msh.name
					format "It is possible that there are vertices that the importer failed to find/parse.\n"
				)
			)
		)
		else
		(
			Messagebox "For some reason, we could not build mesh!"
		)
	)
	
	Append		data_array[9]		_nodesM_arr
	
	
	if data_array[3][2].count > 0 then
	(
		meshBuilderSub \
								data_array \
								info
	)
	
	format "Done parsing meshes\n"
)




--////////////////////////// Inverse Transformation Matrix ///////////////////////////
--NOTES this is read from the .inv_trans_mats files
inv_matrix_arr = #()
matrix_arr = #()

fn read_inv_trans_matrices \
										bstream =
(
	inv_matrix_arr = #()
	matrix_arr = #()
	
	bn_flag1 = readlong bstream
	numBones = readlong bstream
	
	-- reading the 4 rows of the matrix3 (the 4th row is the translation) (then we inverse the matrix - because twr2 uses an inverse matrix)
	for i=1 to numBones do
	(
		rot_p3 = point3 0 0 0 --create a point3 for the 4th row
		matrix = matrix3 1

		--row 1
		x = (readfloat bstream);y = (readfloat bstream);z = (readfloat bstream)
		matrix[1] = [x,y,z]
		
		--row 2
		x = (readfloat bstream);y = (readfloat bstream);z = (readfloat bstream)
		matrix[2] = [x,y,z]
		
		--row 3
		x = (readfloat bstream);y = (readfloat bstream);z = (readfloat bstream)
		matrix[3] = [x,y,z]
		
		--row 4
		px = (readfloat bstream); py = (readfloat bstream); pz = (readfloat bstream)		
		rot_p3 = [px,py,pz]
		matrix[4] = rot_p3
		
		Append inv_matrix_arr matrix
	)	
)



--////////////////////////// Read bone names and hierarchy ///////////////////////////
struct _bones
(
	_name = "",
	_parent = 0
)

bones_pos_arr = #()
bones_posAnim_arr = #() --for the animation

struct _bones_pos
(
	_pos = point3 0 0 0,
	_quat = quat,
	_matrix31 = Matrix3 1
)

fn read_boneString nChars bstream =
(
	_string = ""
	
	for i=1 to nChars do
	(
		_string += bit.intAsChar (ReadByte bstream #unsigned)
	)
	
	return _string
)

fn decompress_quat x y z w =
(	
	--// Dequantisize the 16bit signed integers into float quaternion components
	--d = 32767.0
	--_scale = (sqrt 2)
	
	x					= x/0x7FFF as float -- OBSOLETE --> the highest value that --> (s0-0x3FFF)/0x7FFF    can take is  (32767-16383)/32767) = +-~0.5
	y					= y/0x7FFF as float
	z					= z/0x7FFF as float
	-- w = sqrt(1-(s0^2+s1^2+s2^2))
	w					= w/0x7FFF as float
	
	q					= quat x y z w
	
	return q;
)

--This is read from the .anim files
fn read_bone_names_hierarchy \
											bstream =
(	
	boneIndexA				= #()
	boneIndexB				= #()
	
	bone_arr				= #()
	skelName				= ""
	numBones				= 0

	anim_type				= readlong bstream
	anim_meshFlag		= readlong bstream
	FPSanim					= readfloat bstream


	--Read the Skeleton Name
	numChars_skelName	= readshort bstream --num chars to read
	skelName				= read_boneString (numChars_skelName) (bstream)

	--unknowns ( frame info???)
	u1							= readlong bstream -- this may always be 0x3DCCCCCD (?)
	
	numBones				= readlong bstream
	
	if numBones > 0 then
	(
		for i = 1 to numBones do
		(
			str_bones = _bones()
				
			numChars = readshort bstream		
			str_bones._name = read_boneString (numChars) (bstream)
			str_bones._parent = readlong bstream

			Append bone_arr str_bones
		)

		--for some reason there is a count of each bone here, and the count is made twice
		for i=1 to numBones do
		(
			num = readlong bstream
			Append boneIndexA num
		)

		--second bone count
		for i=1 to numBones do
		(
			num = readlong bstream
			Append boneIndexB num
		)

		numBonesA = readlong bstream
		numBonesB = readlong bstream
		numFrames = readlong bstream
		
		for f=1 to numFrames do
		(
			str_bones_pos = _bones_pos()
			Append (bones_pos_arr) #()	
		)

		for f=1 to numFrames do
		(
			for i=1 to numBonesA do
			(
				str_bones_pos = _bones_pos()
				Append (bones_pos_arr[f]) (str_bones_pos)
			)
			
			--the translations ( 3 x float = 12 bytes )
			for i=1 to numBonesA do
			(
				--// read translation (3 floats)
				--read translation (3 floats)
				posX = readfloat bstream-- ; if bit.isNAN transX then (transX = 0)
				posY = readfloat bstream-- ; if bit.isNAN transY then (transY = 0)
				posZ = readfloat bstream-- ; if bit.isNAN transZ then (transZ = 0)
				
					bones_pos_arr[f][i]._pos= [posX, posY, posZ]
					bones_pos_arr[f][i]._matrix31[4] = [posX, posY, posZ]		
				--//end of translation
			)
			
			for i=1 to numBonesA do
			(
				qx = (readshort bstream) as float
				qy = (readshort bstream) as float
				qz = (readshort bstream) as float
				qw = (readshort bstream) as float			

				q = decompress_quat qx qy qz qw
				bones_pos_arr[f][i]._quat = q
			)
		)

		--Build the bone hierarchy
		if bones_array.count == 0 then-------------------------------------------------------------------------------------------------------------------------------------------??
		(
			bones_array = #()
			for f=1 to 1 do --just 2 frames are located in the .anim files and only 1 is needed, because the second frame is identical to the first
			(
				for i=1 to numBones do
				(
					BoneParentID = bone_arr[i]._parent
					boneLength = length bones_pos_arr[f][i]._pos--0.07		

					matrix_arr[i] = inverse inv_matrix_arr[i]
					
					startPos = matrix_arr[i].translationpart --The location of the new bone as point3	
					endPos = (matrix_arr[i].translationpart + (boneLength*(normalize matrix_arr[i][1]))) --The direction (X axis) of the bone and the bone length as point3
					zAxis = (normalize matrix_arr[i][3]) --The direction of the Z axis for the new bone node as point3

					--	--newBone = bonesys.createbone	       tfm.row4     (tfm.row4 + 0.01 * (normalize tfm.row1))      (normalize tfm.row3)
					newbone = BoneSys.createBone (startPos) \
																(endPos)  \
																(zAxis)	
					
					newBone.name = bone_arr[i]._name --+ "(" + BoneParentIDName + ")"	
							---------------------------------------------------------------------------
							newBone.length = 0--.07 --shaded meshbone (can be set to zero)
							newBone.width = 0--.01 --shaded meshbone (can be set to zero)
							newBone.height = 0--.01 --shaded meshbone (can be set to zero)
							---------------------------------------------------------------------------
						
					newBone.wirecolor = yellow
					newbone.showlinks = true
					newBone.setBoneEnable false 0
					newBone.pos.controller = TCB_position ()
					newBone.rotation.controller = TCB_rotation ()
					
					-------
					newBone.transform.translation = matrix_arr[i].translationpart
					-------
						
					append bones_array newBone	
					
					if BoneParentID != -1 then --if 0xffffffff then the bone does not have a parent
					(
						newBone.parent = bones_array[BoneParentID+1] --we have to add +1 here since Max Arrays are NOT Zero Based!		
					)	
				)
			)
		)-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------??
	)	
	return bones_array
)

--/////////////// Add skin modifier to mesh ///////////////
fn addSkinMod \
						objArr =
(
	for n=1 to objArr.count do
	(
		for x=1 to objArr[n].count do
		(
			for x2=1 to objArr[n][x].count do
			(
				_mesh = objArr[n][x][x2]
			
				clearselection()
				max modify mode
				select _mesh
				modPanel.addModToSelection (Skin()) ui:on	
			)
		)
	)
)


--////////////////// Add bones to skin //////////////////
fn addBones2Skin \
							_bones_array \
							objArr =
(
	max modify mode
	
	
	for n=1 to objArr.count do
	(
		for x=1 to objArr[n].count do
		(
			for x2=1 to objArr[n][x].count do
			(
				_mesh = objArr[n][x][x2]
			
				if iskindof _mesh Editable_mesh then
				(
					if classof _mesh.modifiers[1] == skin then
					(
						theSkin = _mesh.modifiers[1]
						modPanel.setCurrentObject theSkin
							
						for _bone in _bones_array do
						(
							skinOps.addbone theSkin _bone  1
						)
					)
				)
			)
		)
	)	
)

--////////////////// Set Weights //////////////////
fn set_weights \
						data_array \
						objArr =
(
	--/* temp off
	--////////////////////////////////   Zero out all weights first for all vertices and all meshes  ////////////////////////////////
	
	for sx=1 to objArr.count do
	(
		--ZERO out vertices
		for obj=1 to objArr[sx].count do
		(
			for x2=1 to objArr[sx][obj].count do
			(
				-------------------------------
				clearSelection() --deselect everything
				-------------------------------
					
				theMesh = objArr[sx][obj][x2].mesh		
				nVerts = getnumverts objArr[sx][obj][x2].baseobject.mesh	--<------- the nVerts (the vert count for each current mesh)
				theSkin = objArr[sx][obj][x2].modifiers[1]
				faceID = getFaceMatID theMesh 1 --// get the faceIDs of the current mesh
							
					-------------------------------
					select objArr[sx][obj][x2] --select only the current looped mesh
					max modify mode --enter modify mode (we must do that inorder to add weights to the skin modifier)
					modPanel.setCurrentObject theSkin --we must set the current skin in the modpanel, else we can't add weights
						--// REPORT (a check to see that the modpanel is active and the current modifier is the skin (which we will add weights to)
						checkmod = modPanel.getCurrentObject()
						format "CURRENT: %\n" checkmod
					-------------------------------	
					
				nBones = skinOps.GetNumberBones theSkin
							
				--//---------------------This is the array for applying zero weights before adding the real weights---------------------
				BoneIDIndex = #() --this is the index with the correct BoneIDs NOTE (id-1 because max ids are not zero based)
				for n=1 to nBones do
				(
					Append BoneIDIndex (skinOps.GetBoneIDByListID theSkin n)
				)	
					
				--// fill an array with zero weights to reflect the size of the array that contains the bones for the current skin
				zeroWeights = #()
				for x=1 to BoneIDIndex.count do
				(
					Append zeroWeights (0.0 as float)
				)
					
				format "nVerts: %\n" nVerts
				format "nBones: %\n" nBones
					
				format "CURRENTLY ZEROING OUT VERTICES Please Wait...\n"			
				--/////////////////////   First apply zero weights to ALL verts in current looped mesh   /////////////////////
				for v=1 to nVerts do --loop the size of nNumVerts as described in the MeshSubset info --all verts for all meshes (the above loop should be used instead)
				(
					--remove current weights (zero them out, we want to start with no weights) -- temp off
					skinOps.ReplaceVertexWeights theSkin (v) (BoneIDIndex) (zeroWeights)			
				)
				---------------------------------------------	
			)
		)
		--*/		
		
		--////////////////////////////////  SET THE REAL WEIGHTS  /////////////////////////////////
		nFirstVertId = 0
		nNumVerts = 0

		-------------------------------
		clearSelection() --deselect everything
		-------------------------------
		
		for obj=1 to objArr[sx].count do
		(
			for x2=1 to objArr[sx][obj].count do
			(
				theMesh = objArr[sx][obj][x2].mesh
				
				--nVerts = getNumVerts theMesh	--<------- the nVerts (the vert count for each current mesh)
				theSkin = objArr[sx][obj][x2].modifiers[1]
							
				-------------------------------
					select objArr[sx][obj][x2] --select only the current looped mesh
					max modify mode --enter modify mode (we must do that inorder to add weights to the skin modifier)
					modPanel.setCurrentObject theSkin --we must set the current skin in the modpanel, else we can't add weights
						--// REPORT (a check to see that the modpanel is active and the current modifier is the skin (which we will add weights to)
						checkmod = modPanel.getCurrentObject()
						format "CURRENT: %\n" checkmod
				-------------------------------					

				nFirstVertId = 0
				nNumVerts = getnumverts objArr[sx][obj][x2].baseobject.mesh	--<------- the nVerts (the vert count for each current mesh)		
		-- 		nNumVerts = getnumverts objArr[obj].mesh	--<------- the nVerts (the vert count for each current mesh)
				
				--// REPORT
				format "CURRENTLY APPLYING WEIGHTS TO: % Please Wait...\n" objArr[sx][obj][x2].name
							
				--/////////////////////   Next apply the real weights to the range of vertices for each mesh as described in the MeshSubset info  /////////////////////
				for v=nFirstVertId+1 to nNumVerts do --loop the size of nNumVerts as described in the MeshSubset info (also not, max is not zero based, so we have to add +1 to "v")	
				(
					--data_array[3][1].weights_arr
					
					local BonesIDs_x_2 = #()
					local Weights_x_2 = #()

					i=2						
					while i > 0 do --apply weights backwards, because the zero weights (Representing IDs of 1 in our script) come last in the cgf/chr and they are applied, the last bones are reapplied the wrong value of zero.
					(	
						local bonesIDs = 0
						local weight = 0.0
									
						if i == 1 then --bone1
						(
							bonesIDs = data_array[3][sx][obj][x2].weights_arr[v].bone1+1 --our max bones start at 1 and not zero, therefor we must add +1
							weight = data_array[3][sx][obj][x2].weights_arr[v].weight1
						)
						else if i == 2 then --bone2
						(
							bonesIDs = data_array[3][sx][obj][x2].weights_arr[v].bone2+1 --our max bones start at 1 and not zero, therefor we must add +1
							weight = data_array[3][sx][obj][x2].weights_arr[v].weight2
						)
									
						Append   (BonesIDs_x_2)   (bonesIDs)							
						--add 2 weights to array
						Append   (Weights_x_2)   (weight) --the CrySkinVtx structs
									
						i -= 1 --decrement
					)
								
					skinOps.SetVertexWeights theSkin (v) (BonesIDs_x_2) (Weights_x_2)
					
					/*
					--DEBUG
					if v==1 then format "_____________----- applying weights for mesh: % ------_____________\n" objArr[obj].name
					if v==1 then format "_____________----- nNumVerts: % ------_____________\n" nNumVerts
					--if v == nNumVerts then print BonesIDs_x_2
					if v==1 then print data_array[3][1].weights_arr.count			
					--End of DEBUG
					--*/
					
					--Free the Arrays
					free BonesIDs_x_2
					free Weights_x_2
				)
				
				--//REPORT
				format "DONE APPLYING WEIGHTS --- OK!\n"
			)
		)
	)
)

fn rotate_models =
(
	--------------------------------------Rotate via Group--------------------------------------
	select objects
	
	if selection.count != 0 then
	(	
		--create a temporary group
		grp = group selection name:"tempGroup"

		nRot = 1
		rot_x = 1
		rot_y = 0
		rot_z = 0

		--rotate the group
		for times=1 to nRot do
		(							
			in coordsys world
			rotate grp (angleaxis 90 [rot_x,rot_y,rot_z])
		)
		
		--destroy the temporary group, it is not needed any longer
		-------------------------------------------------------------------
		ungroup $tempGroup
		-------------------------------------------------------------------
	)
	else
	(
		format "No objects to select!"
	)
)


------------------=========================================================================================
frames = #()
motionAnimBoneTable = #(#(),#())
--the first dimension is the boneidx, the 2nd is the translation or quaternion
_pos = #(#(),#()) --position updates (usually these are very few bones, often 1, if any) [1]=boneindex [2]=pos
_quat = #(#(),#()) --usually ALL bones [1]=boneindex [2]=rot


--This is read from the .anim motion files-------------------------------------------------------------------------------------
fn read_anim_keys \
							bstream =
(		
	bone_arr = #()
	skelName = ""
	numBones = 0

	anim_type = readlong bstream
	
	--// 0x00000000 seems to be non-rigged rigidmodels(oars boats and stuff etc...)
	--// 0x00000001 seems to be variantmesh rigged with skeleton,
	anim_meshFlag = readlong bstream 
	
	global FPS = readfloat bstream	

	--Read the Skeleton Name
	numChars_skelName = readshort bstream --num chars to read
	skelName = read_boneString (numChars_skelName) (bstream)

	--unknowns ( frame info???)
	u1 = readfloat bstream -- 0.5 but what is it?
	
	numBones = readlong bstream --total number of bones	
	
	--since we read this from the skeletal .anim file, we probably do not have to read it again...
	---but we do it anyway, else, why would it be listed  in the motionAnim again?
	for i=1 to numBones do
	(
		str_bones = _bones()
			
		numChars = readshort bstream		
		str_bones._name = read_boneString (numChars) (bstream)
		str_bones._parent = readlong bstream

		Append bone_arr str_bones
	)

	--format "_____________________you are here: %\n" (ftell bstream)
	--Add the listing of the boneTable (before the animation) to a 2D array	

	--// Set A = --TRANSLATION-- updates for bones (-1) indicates the bone has no pos/translation update
	for i=1 to numBones do
	(
		local val = (readlong bstream)
		Append motionAnimBoneTable[1] val --index of the bone will get the counter value i, since in the anim file, (-1)s are counted (but not used)
	)

	--// Set B = bones that have --ROTATIONS-- (usually for all bones)
	for i=1 to numBones do
	(
		local val = (readlong bstream)
		Append motionAnimBoneTable[2] val
	)

	posBones = readlong bstream --Test these, * the number of frames
	rotBones = readlong bstream --Test if these are the initial positions for the bones
	global numFrames = readlong bstream --frame count
	global animLength = (numFrames/FPS) --length of animation in seconds
	
	--REPORT
-- 	format "_____________________you are here: %\n" (ftell bstream)
-- 	format "_________frames: %\n" numFrames
	
	if (anim_type == 0x00000005) AND \ --.variantmeshdefinition
		(anim_meshFlag == 0x00000001) then
	(
		-------------- Add the translations and rotations for each frame --------------
		for f=1 to numFrames do
		(
			Append frames #() --append the current frame to the array
			
			_pos = #(#(),#())
			_quat = #(#(),#())		
		
			for x=1 to motionAnimBoneTable[1].count do
			(
				if motionAnimBoneTable[1][x] !=(-1) then
				(
					--read translation (3 floats)
					posX = readfloat bstream
					posY = readfloat bstream
					posZ = readfloat bstream
						
					Append _pos[1] motionAnimBoneTable[1][x] --add the boneIndex
					Append _pos[2] [posX, posY, posZ] --add the translation
				)
				else
				(
					Append _pos[1] motionAnimBoneTable[1][x] --add the boneIndex
					Append _pos[2] undefined --add the translation
				)
			)

			for x=1 to motionAnimBoneTable[2].count do
			(
				if motionAnimBoneTable[2][x] != (-1) then
				(
					qX = readshort bstream
					qY = readshort bstream
					qZ = readshort bstream
					qW = readshort bstream
						
					--Decompress the quaternion
					local dQuat = ( decompress_quat qX qY qZ qW )
										
					Append _quat[1] motionAnimBoneTable[2][x] --add the boneIndex
					Append _quat[2] dQuat
				)
				else
				(
					Append _quat[1] motionAnimBoneTable[2][x] --add the boneIndex
					Append _quat[2] undefined --add the translation
				)
			)		
			
			Append frames[f] _pos
			Append frames[f] _quat
		)
	)
	else if (anim_type == 0x00000005) AND \ --.rigid_model_v2
			(anim_meshFlag == 0x00000000) then
	(
		-------------- Add the translations and rotations for each frame --------------
		for f=1 to numFrames do
		(
			Append frames #() --append the current frame to the array
			
			_pos = #(#(),#())
			_quat = #(#(),#())		
		
			for x=1 to motionAnimBoneTable[1].count do
			(
				--//////////// The translations will be added if the bone is not 0xFFFFFFFF ////////////
				--read translation (3 floats)
				posX = readfloat bstream
				posY = readfloat bstream
				posZ = readfloat bstream				
				
				if motionAnimBoneTable[1][x] !=(-1) then
				(
					Append _pos[1] motionAnimBoneTable[1][x] --add the boneIndex
					Append _pos[2] [posX, posY, posZ] --add the translation
				)
				else
				(
					Append _pos[1] motionAnimBoneTable[1][x] --add the boneIndex
					Append _pos[2] undefined --add the translation
				)
			
				
				
				
				--//////////// The rotations(as quaternions) will be added if the bone is not 0xFFFFFFFF ////////////
				qX = readshort bstream
				qY = readshort bstream
				qZ = readshort bstream
				qW = readshort bstream
						
				--Decompress the quaternion
				local dQuat = ( decompress_quat qX qY qZ qW )
				
				if motionAnimBoneTable[2][x] != (-1) then
				(										
					Append _quat[1] motionAnimBoneTable[2][x] --add the boneIndex
					Append _quat[2] dQuat
				)
				else
				(
					Append _quat[1] motionAnimBoneTable[2][x] --add the boneIndex
					Append _quat[2] undefined --add the translation
				)
			)
			
			Append frames[f] _pos
			Append frames[f] _quat
		)
	)
)

fn inject_anim_keys \
							num_Frames \
							bones_array \
							frames =
(	
	animationRange = interval (0f) ((num_Frames-1.0))
	--framerate = FPS
	
	----------------Set time configuration----------------
	timeConfiguration.playbackSpeed = 1
	timeConfiguration.realTimePlayback = true
	timeConfiguration.playbackLoop =  true	
	
	
	with animate on
	(
		--/*
		--TRANSLATION (excluding the root)
		for i=1 to num_Frames do
		(			
			------------------Array map-------------------
			--[frame] frame

			--[frame][1][1] bone index
			--[frame][1][2] positions/translations

			--[frame][2][1] bone index
			--[frame][2][2] quaternion
			-------------------------------------------------
			
			
			at time (i-1) --frames start at zero (unusual for maxscript which is based on 1 index arrays)
			(
				--update position for each bone
				for theBone = 1 to frames[i][1][1].count do
				(
					if frames[i][1][1][theBone] != (-1) then
					(					
						idx		= theBone --the bone to translate					
						trans		= frames[i][1][2][idx] --the point3 translation
						initPos	= copy matrix_arr[idx]
						_bone	= bones_array[theBone]	
				
						if idx > 1 then --if not the root bone
						(
							in coordsys parent
							(
								_bone.position = trans								
							)
						)
					)
				)				
			)
			
		)
		--*/
		
		--/*
		--TRANSLATIONS - ONLY ROOT ( which is essentially translating the whole object via the root)		
		--this is so that we can chose whether to animate the root (i.e. translating the whole object from its starting position)
		if animateRoot then
		(		
			for i=1 to num_Frames do
			(
				at time (i-1) --frames start at zero (unusual for maxscript which is based on 1 index arrays)
				(
					--update position for the root bone
					for theBone = 1 to frames[i][1][1].count do
					(
						if frames[i][1][1][theBone] != (-1) then
						(
							idx		= theBone --the bone to translate
							trans		= frames[i][1][2][idx] --the point3 translation
							initPos	= copy matrix_arr[idx]
							_bone	= bones_array[theBone]
							
							if idx == 1 then --the root bone
							(
								in coordsys world
								(								
									_bone.position = trans --posMatrix.row4 + bones_pos_arr[1][idx]._pos								
								)
							)
						)
					)
				)
			)
		)
		--*/		
		
		--old rotation
		/*
		-- ROTATION as quaternion
		for i=1 to num_Frames do
		(
			at time (i-1) --frames start at zero (unusual for maxscript which is based on 1 index arrays)
			(
				--bones_pos_arr[1][i]._pos  --from the anim (not motion, but the one alon the inv_trans_mat file)
				--update position for each bone
				for theBone = 1 to frames[i][2][1].count do
				(
					if frames[i][2][1][theBone] != (-1) then
					(					
						idx		= theBone --the bone to translate (its index)
						_quat	= frames[i][2][2][theBone] --the point3 translation
						_bone	= bones_array[theBone]
						
						--store a copy of the translation before the rotation
						transTemp = copy bones_array[theBone].transform.row4
						
						in coordsys parent
						(							
							_bone.rotation = _quat
						)
						
						--restore translationpart
						_bone.pos = transTemp------------------------------
					)
				)
			)
		)
		--*/		
		
		
		--/*
		-- ROTATION as quaternion
		for i=1 to num_Frames do
		(
			at time (i-1) --frames start at zero (unusual for maxscript which is based on 1 index arrays)
			(
				--bones_pos_arr[1][i]._pos  --from the anim (not motion, but the one alon the inv_trans_mat file)
				--update position for each bone
				for theBone = 1 to frames[i][2][1].count do
				(
					if frames[i][2][1][theBone] != (-1) then
					(						
						_quat	= frames[i][2][2][theBone] --the point3 translation
						_bone	= bones_array[theBone]
						
						--store a copy of the translation before the rotation
						transTemp = copy bones_array[theBone].transform.row4
						
						--skipping the bn_lefteye and bn_lefteyebrow1, but where is the info that tells us to do that???
						if (NOT matchpattern _bone.name pattern:"*bn_lefteye*") OR \
							(NOT matchpattern _bone.name pattern:"*bn_lefteyebrow1*") then						
						(
							in coordsys parent
							(							
								_bone.rotation = _quat
							)
						)
						/* -- skip REPORT (we can always turn it on when debugging
						else
						(
							format "Skipping Animation of Bone: % \t Index: %\n" _bone.name theBone					
						)						
						--*/
						
						--//restore translationpart
						bones_array[theBone].pos = transTemp
					)
				)
			)
		)
		--*/
		
	)	
	
)

--//////////////////////////////////// End of Mesh and Animation Parsing ////////////////////////////////////




--//////////////////////////////////// New functions //////////////////////////////////// 
fn read_csv animFile =
(
	f = Openfile animFile
		
	while Not eof f do
	(
		aline = readDelimitedString f ","
		--since we are skipping a line after the delimiterstring, we want to check again that we do not
		--skip to a line beyond the end (nonexistent line)
		if NOT eof f then
		(
			skipToNextLine f
		)
		Append animList_arr (trimright (trimleft aline  "\" ")  "\" ")
	)
	close f
)	

fn walkdir_xml \
					dir \
					pattern \
					arr =
(
	if (dir != undefined) and \
		(pathconfig.islegalpath dir) then
	(
		dirArr = GetDirectories (dir + "\\*")
	 
		for d in dirArr do
		(
			join dirArr (getDirectories (d + "\\*"))
		)
	 
		append dirArr (dir + "\\") -- Need to include the original top level directory
	 
		for f in dirArr do
		(
			arr = (getFiles (f + pattern))		
		)
		
		return arr;
	)
)

struct infoStruct
(
	rootPath = "",
	numAnimFiles = "",
	num_xmlTemplates = "",
	num_xmlDefinitions = ""
)

fn make_info_array \
							infoType \
							toAdd \
							str =
(
	if infoType == "rootPath" then
	(
		str.rootPath = "rootPath: " + (toAdd as string)
	)
	else if infoType == "numAnimFiles" then
	(
		str.numAnimFiles = "Num Anim Files: " +  (toAdd as string)
	)
	else if infoType == "num_xmlTemplates" then
	(
		str.num_xmlTemplates = "Num XML Templates: " +  (toAdd as string)
	)
	else if infoType == "num_xmlDefinitions" then
	(
		str.num_xmlDefinitions = "Num XML Definitions: " + (toAdd as string)
	)
	
	info = #()	
	Append info str.rootPath
	Append info str.numAnimFiles
	Append info str.num_xmlTemplates
	Append info str.num_xmlDefinitions
)

fn restore_bindPose =
(
	if (skeleton_type_arr.count != 0) then
	(	
		for i=1 to skeleton_type_arr.count do --for now this is only 1, and it is doubtful we will ever need more than 1
		(
			if skeleton_type_arr[i] != "" then
			(
				--Close binary streams if they are open
				if (bsAN == true) then
				(
					fclose bsAn
				)
				
				--Close binary streams if they are open
				if (bsbm == true) then
				(
					fclose bsbm
				)
				----- End of close bin streams -----
					
				
				
				sliderTime = 0f
				deleteKeys objects #allKeys				

				--------------------------------------------------------------------------------------------------------------------------
				skeletonName = skeleton_type_arr[i]	
				goAheadReset = false
				bone_inv_trans_mats = undefined
				anim = undefined				
				

				--Is any mesh file at all in the scene associated with a skeleton data? returns bool
				hasSkeleton = have_Skeleton_check_rootData()

				--get the name of the current skeleton in the skeleton array
				skelName = skeleton_type_arr[i]
				skel_arr = #()
				
				if hasSkeleton == true then
				(	
					for dx=1 to rootData[2].count do
					(
						Append skel_arr rootData[2][dx][6][1].skeleton_type
					)
					
					--if the new skeleton name (newAnimName) matches the one we are currently using then skelIDX will return the index
					--else it will return 0 (we are only interested in at least one match)
					skelIDX = finditem	skel_arr (getFilenameFile skeletonName)
					if skelIDX != 0 then
					(
						currMeshSkel = skel_arr[skelIDX]
						
						--if the names of the skeleton name in the skeleton array matches any name in the data_array[6][1].skeleton_type
						if skelName == currMeshSkel then	
						(									
							--// Prepare the paths
							ext_bone_inv_trans_mats = ".bone_inv_trans_mats"
							ext_anim = ".anim"
										
							bone_inv_trans_mats = pathconfig.appendpath \
																							(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																							(currMeshSkel + ext_bone_inv_trans_mats)

							anim = pathconfig.appendpath \
																		(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																		(currMeshSkel + ext_anim)
							
							
							if (doesfileexist bone_inv_trans_mats) AND \
								(doesfileexist anim) then
							(										
								--check if the skeleton names match
								bsAn = fopen anim "rb"
								------------------------------------
									fseek bsAn 12 #seek_set
									stringLength = readshort bsAn
									skeletonName = ReadFixedString bsAn stringLength						
								------------------------------------
								fclose bsAn										
										
								goAheadReset = true
										
								--at least one match is needed only
							)
						)
					)

					if skelName == currMeshSkel then	
					(									
						--// Prepare the paths
						ext_bone_inv_trans_mats = ".bone_inv_trans_mats"
						ext_anim = ".anim"
										
						bone_inv_trans_mats = pathconfig.appendpath \
																						(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																						(currMeshSkel + ext_bone_inv_trans_mats)

						anim = pathconfig.appendpath \
																	(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																	(currMeshSkel + ext_anim)
																				
									
						if (doesfileexist bone_inv_trans_mats) AND \
							(doesfileexist anim) then
						(										
							--check if the skeleton names match
							bsAn = fopen anim "rb"
							------------------------------------
								fseek bsAn 12 #seek_set
								stringLength = readshort bsAn
								skeletonName = ReadFixedString bsAn stringLength						
							------------------------------------
							fclose bsAn										
										
							goAheadReset = true
										
							--at least one match is needed only
						)
					)
				)
					
				if goAheadReset == true then
				(
					safe2rotate = true
					
					bsAn = fopen anim "rb"
					bsbm = fopen bone_inv_trans_mats "rb"						
					------------------------------------------

					----------------- restore bindPose -----------------
					--sliderTime = 0f
					--deleteKeys objects #allKeys
					frames = #()
					motionAnimBoneTable = #(#(),#())
					--the first dimension is the boneidx, the 2nd is the translation or quaternion
					_pos = #(#(),#()) --position updates (usually these are very few bones, often 1, if any) [1]=boneindex [2]=pos
					_quat = #(#(),#()) --usually ALL bones [1]=boneindex [2]=rot
					-------------------------------------------------------
						
					inv_matrix_arr = #()
					matrix_arr = #()		
									
					--read inv matrices for the bones
					read_inv_trans_matrices \
														bsbm
									
					if (bones_array.count == 0) AND \
						(skeleton_type_arr.count == 0) then
					(
						--read bones hierarchy
						bones_array = read_bone_names_hierarchy \
																					bsAn
					)
						
					------------------------------------------					
					fclose bsbm
					fclose bsanim

					--if bones_array.count == 0 then
					if bones_array.count != 0 then
					(
						for i=1 to bones_array.count do
						(
							_bone = bones_array[i]
								
							matrix_arr[i] = inverse inv_matrix_arr[i]

							--skipping the bn_lefteye and bn_lefteyebrow1, but where is the info that tells us to do that???
							if (NOT matchpattern _bone.name pattern:"*bn_lefteye*") OR \
								(NOT matchpattern _bone.name pattern:"*bn_lefteyebrow1*") then
							(
								-------
								_bone.transform = matrix_arr[i]
								-------
							)
							else
							(
								format "Skipping Rotation Restoration for Bone: % \t Index: %\n" _bone.name i				
							)
						)
					)					
				)
				else
				(
					safe2rotate = false
					
					format "skeletonName: %\n"								skeletonName
					format "str_header.skeleton_type: %\n"				str_header.skeleton_type
					format "ERROR - Skeletons do not match, can't restore Bind Pose! (called by restore_bindPose())\n"
				)				
				--------------------------------------------------------------------------------------------------------------------------
			)
		)
	)		
)

--////////////////// Read XML //////////////////
--REPORT
fn read_xml_array \
							str_read_xml \
							xmlFile \
							type =
(
	--str = undefined	
-- 	str = str_read_xml
-- 	str.report = true
	
	str_read_xml = read_xml()
	str_read_xml.report = true	
	str = #()
	
	if type == "template" then
	(		
		--read template
		str = str_read_xml.main \
						xmlFile \
						str_read_xml._xml_template
	)
	else if type == "definition" then
	(		
		--read definition
		str = str_read_xml.main \
						xmlFile \
						str_read_xml._xml
	)
	
	for i=1 to str.count do
	(
		-- 	str_read_xml.format_tabs str_read_xml._xml[i].depth
		-- 	print str_read_xml._xml[i]
		
		format "%\n" str[i].attribs[1].count
		for a=1 to str[i].attribs[1].count do
		(
			_name = str[i].attribs[1][a]
			_value = str[i].attribs[2][a]
			
			if _name != undefined AND _value  == "bodyparts" then
			(
				format "_name: %\n" _name
				format "_name: %\n" _value
				
				if i != str_read_xml._xml.count then
				(
					_name = str[i+1].attribs[1][a]
					_value = str[i+1].attribs[2][a]
					
					if _name == "model" then
					(
						format "_name: %\n" _name
						format "_name: %\n" _value
						
						g_rmv2 = pathConfig.appendPath \
																	(getinisetting CONST_CONFIG_PATH "root" "rootpath") \
																	_value
					)
				)
			)
		)
	)
)
--////////////// End of Read XML //////////////


fn fill_xml_arrays \
						str \
						xmlFile \
						type =
(
	if (xmlFile != undefined) AND \
		(pathConfig.isLegalPath xmlFile) AND \
		(doesfileexist xmlFile) then
	(		
		--///////////////////////////// Read XML ////////////////////////////////
		str_read_xml = read_xml()
		str.report = true
		
		_xml = #() --definition
		_xml_template = #() --template		

		if type == "definition" then
		(
			--read definition
			_xml = str_read_xml.main \
									xmlFile \
									str_read_xml._xml
		)
		else if type == "template" then
		(			
			--read template
			_xml_template = str_read_xml.main \
												xmlFile \
												str_read_xml._xml_template
		)
		--////////////////////////////////////////////////////////////////////////
		
		read_xml_array \
								str \
								xmlFile \
								type
	)
)

fn set_attachPoints \
							meshPath =
(
-- 	for i=1 to SEPARATED_DEFS_ARR.count do
-- 	(
-- 		_random_full_path_2_compare = (pathconfig.appendpath rootpath SEPARATED_DEFS_ARR[i]._random) 
-- 		
-- 		
-- 		if meshPath == _random_full_path_2_compare then
-- 		(
-- 			print "the meshpath matched the SEPARATED_DEFS_ARR[count]._random ********************"
-- 							
-- 			if SEPARATED_DEFS_ARR[i]._attach_points.count > 0 then
-- 			(									
-- 				if (SEPARATED_DEFS_ARR[i]._attach_points[1].count >= 4) AND \
-- 					(SEPARATED_DEFS_ARR[i]._attach_points[1][1] == "name") then
-- 				(
-- 					weapon_type = SEPARATED_DEFS_ARR[i]._attach_points[1][2]
-- 								
-- 					format "weapon_type: %\n" weapon_type
-- 								
-- 					if SEPARATED_DEFS_ARR[i]._attach_points[1][3] == "attach_point" then
-- 					(
-- 						bone2attach2 = SEPARATED_DEFS_ARR[i]._attach_points[1][4]
-- 												
-- 						format "bone2attach2: %\n" bone2attach2
-- 						
-- 						for x=1 to MESH_NODES_4_attachPoints_arr.count do
-- 						(
-- 							idx = finditem MESH_NODES_4_attachPoints_arr[x][3] meshPath							
-- 							
-- 							if idx > 0 then --the meshPath matched
-- 							(
-- 								masterID = MESH_NODES_4_attachPoints_arr[x][1][1] --get the id of the matched meshPath
-- 								
-- 								format "masterID: %\n" masterID
-- 								format "_attach_boneNumber_arr[x]: %\n" _attach_boneNumber_arr[x]
-- 								
-- 								--get the active bones for this meshname, use x counter
-- 								for x2=1 to _attach_boneNumber_arr[x].count do
-- 								(
-- 									activeBoneID = _attach_boneNumber_arr[x][x2]
-- 									
-- 									format "activeBoneID: %\n" activeBoneID
-- 									
-- 									
-- 									if activeBoneID != -1 then
-- 									(	
-- 										_meshNode = MESH_NODES_4_attachPoints_arr[x][1][1]
-- 										
-- 										_meshNode.transform = bones_array[masterID].transform										
-- 										_meshNode.parent = bones_array[masterID]
-- 										
-- 										format "_meshNode.name: %\n" _meshNode.name
-- 										
-- 									)
-- 								)
-- 							)
-- 						)
-- 					)
-- 				)
-- 			)
-- 			else
-- 			(
-- 				format "No Attach Points found!\n"
-- 			)
-- 		)
-- 	)
	
	--print _attach_boneNumber_arr
	
	--////////////////////// Set Crests Attach Points //////////////////////
	for i=1 to SEPARATED_DEFS_ARR.count do
	(
		if SEPARATED_DEFS_ARR[i]._random_crest != "" then
		(
			if (SEPARATED_DEFS_ARR[i]._NESTED[1].count > 1) AND \
				(SEPARATED_DEFS_ARR[i]._parentVal[1] == "helmets") then
			(
				
				_crestParent_meshFile			= pathConfig.appendPath rootPath SEPARATED_DEFS_ARR[i]._random --full path of helmet mesh file
				
				_crestMeshFile					= pathConfig.appendPath rootPath SEPARATED_DEFS_ARR[i]._random_crest --full path of the crest meshfile
				_crestMeshNode					= ""
				
				/*
				We need to get aALL THE CRESTS MESH, master and submeshes, belonging to the helmet mesh file, as we did with the weapons, but here we probably
				also need to attach each lod to its corresponding lod! We must find a way to sort them as such, but first, test to apply the matrix and parent relationship
				successfully, because we still have problems with that.
				--*/				
				
				/*
				Now we must look inside the SEPARATED_DEFS_ARR[i]._attach_points to read what name the attach
				point is, and what bone it will attach to (by name). When you have looked at that, then set each mesh.transform in this mesh file
				to the corresponding bone.transform in bones_array (look for the correct bone name in there, finditem), then set the bone as parent to
				the same mesh.
				--*/
				
				_crestMeshNode_arr = #()
				
				for x=1 to MESH_NODES_4_attachPoints_arr.count do
				(
					if _crestMeshFile == MESH_NODES_4_attachPoints_arr[x][3][1] then
					(
						format "------------------------ CREST MATCH -----x: %-----------------------\n" x
						
						Append _crestMeshNode_arr MESH_NODES_4_attachPoints_arr[x][2][1] --collect all the crest mesh nodes in an array
					)
				)
				
				--/*
				
				for crx in _crestMeshNode_arr do
				(
					if iskindof crx Editable_Mesh then
					(
						---------------------------------------
						for x=1 to MESH_NODES_4_attachPoints_arr.count do
						(
							if _crestParent_meshFile == MESH_NODES_4_attachPoints_arr[x][3][1] then
							(
								format "------------------------ MATCH -----x: %-----------------------\n" x
									
								--grab each mesh that has attach points
								_meshNode = MESH_NODES_4_attachPoints_arr[x][2][1] --the meshNode
								
									
								if (SEPARATED_DEFS_ARR[i]._randInt != undefined) AND \
									(SEPARATED_DEFS_ARR[i]._randInt > 0) then
								(
									idx = SEPARATED_DEFS_ARR[i]._randInt --get the random integer we used to pick out the meshfile from the variantdefinition xml
									
									if SEPARATED_DEFS_ARR[i]._NESTED[i][9].count > 0 then --if there are any nested at all
									(
										--for v=1 to SEPARATED_DEFS_ARR[i]._NESTED[idx][4][9][2].count do
										--(													
											attachPoint = SEPARATED_DEFS_ARR[i]._NESTED[i][9][idx][2][4] --name of the attach point, ex: ---> crest_centre
											--format "attachPoint: %\n" SEPARATED_DEFS_ARR[i]._NESTED[i][9][idx][2][4] 		
											
											--A bone will be the parent instead!
	-- 										parentMeshNode = MESH_NODES_4_attachPoints_arr[x][2][1] --ex the helmet to attach the crest to
	-- 										format "parentMeshNode: %\n" parentMeshNode		
											
											if attachpoints_arr[x] != undefined then
											(
												--for nx=1 to attachpoints_arr[i]._names_arr.count do --OFF, we use a finditem as per below instead
												--(											
													findAttachPoint = finditem attachpoints_arr[x]._names_arr attachPoint --find a match to get the index, so we can get the appropriate matrix
												
													if findAttachPoint > 0 then
													(
														--/*
														if MESH_NODES_4_attachPoints_arr[x][4].count > 0 then
														(
															if MESH_NODES_4_attachPoints_arr[x][4][1].count == 2 then
															(
															
																if (classof MESH_NODES_4_attachPoints_arr[x][4][1][1] == Point3) AND \
																	(classof MESH_NODES_4_attachPoints_arr[x][4][1][2] == Point3) then
																(
																	
																	crest_centre = attachpoints_arr[x].matrices_arr[findAttachPoint] --crest_centre matrix
-- 																	crest_centre_inv_inv = inverse crest_centre --crest_centre inverse matrix
																	--format "matrix: %\n" matrix
																		
																	bnx =  attachpoints_arr[x].attachBones_arr[findAttachPoint] -- note: findAttachPoint+1	(max arrays are not zero based)
																	bone2attach2 = bones_array[bnx+1]
																	
																	--we must attach all the crests, all the lods, so we need to get them.
																	
																	--crx.transform.row4[3]			= crx.transform.row4[3] * (-1)
																	crx.parent							= bone2attach2														
																	
																	--[2] is where the data_array is
																	---i = mastermesh
																	
																	--[2][1][1][1] submesh description for master
																	--[2][2][n][1] submesh description for subs
																	
																	--rootData[2][i][2][1][1][1].boundingBox_2verts --mastermesh
																	--rootData[2][i][2][2][n][1].boundingBox_2verts --mastermesh																	
																	
																	
																	------------------------------------------------- Position the Crest ----------------------------------------------------
																	--get center of helmet boundingbox
																	--take the center of the crest
																	--calculate the distance between the points
																	--translate along local y-axix of crest of half the distance (negative)
																															--rootdata[2][2][2][1][i][1].boundingBox_2verts
																	
																	boundingBox_min = MESH_NODES_4_attachPoints_arr[x][4][1][1] --MIN Point3
																	boundingBox_max = MESH_NODES_4_attachPoints_arr[x][4][1][2] --MAX Point3
																	
																	helmetCenter = (boundingBox_min+boundingBox_max)/2 --helmet center calculated from the bounding box -- Point3

																	crx.transform = crest_centre*bone2attach2.transform --good
																		crestCenter = crx.pos --crest center is already correct, just get the pos --Point3
																	
																	CentersDistance = (distance helmetCenter crestCenter) as float --get the distance between the centers
																	
																	FinalTranslate = (CentersDistance/2) as float --get distance divided by 2 and return float
																	
																	--Then finally translate the crest locally along the Y-axis negatively
																	in coordsys local
																	(
																		move crx [0,-FinalTranslate,0]
																	)
																	---------------------------------------------- End of Position the Crest -------------------------------------------------
																)
															)
														)
														--*/

													)												
												--)
											)
										--)								
									)						
								)
							)
						)
						---------------------------------------	
					)	
				)	
				--*/
			)
		)	
		
		
		--////////////////////// Set Attach Points //////////////////////
		if SEPARATED_DEFS_ARR[i]._attach_points.count > 0 then
		(		
			if (SEPARATED_DEFS_ARR[i]._attach_points[1].count == 4) AND \ --is this alwyas 4??????
				(SEPARATED_DEFS_ARR[i]._attach_points[1][1] == "name") then
			(
				meshFile_has_attachPoint = pathConfig.appendPath rootPath SEPARATED_DEFS_ARR[i]._random				
				format "meshFile_has_attachPoint: %\n" meshFile_has_attachPoint
				
				/*
				Now we must look inside the SEPARATED_DEFS_ARR[i]._attach_points to read what name the attach
				point is, and what bone it will attach to (by name). When you have looked at that, then set each mesh.transform in this mesh file
				to the corresponding bone.transform in bones_array (look for the correct bone name in there, finditem), then set the bone as parent to
				the same mesh.
				--*/				
				---------------------------------------
				for x=1 to MESH_NODES_4_attachPoints_arr.count do
				(
					if meshFile_has_attachPoint == MESH_NODES_4_attachPoints_arr[x][3][1] then
					(
						format "------------------------ MATCH -----x: %-----------------------\n" x
						
						--grab each mesh that has attach points
						_meshNode = MESH_NODES_4_attachPoints_arr[x][2][1]
						
						--look inside the attachpoints, what weapon this is, and what bone to attach to in the bones_array (by name)
						for v=1 to SEPARATED_DEFS_ARR[i]._attach_points[1].count do
						(					
							format "attrib/name: %\n" SEPARATED_DEFS_ARR[i]._attach_points[1][v]							
							bone2attach2 = SEPARATED_DEFS_ARR[i]._attach_points[1][4]
						
							for bn=1 to bones_array.count do
							(
								boneName = bones_array[bn].name
								
								if matchpattern boneName pattern:("*"+bone2attach2+"*") then
								(
									--_meshNode.transform	= bones_array[bn].transform
									_meshNode.parent		= bones_array[bn] --set parent
									_meshNode.pos		= bones_array[bn].transform.translationpart
									_meshNode.rotation	= bones_array[bn].transform.rotationpart									
								)
							)
						)

					)
				)
				---------------------------------------				
			)
		)
	)
	
	
/*
		for x=1 to MESH_NODES_4_attachPoints_arr.count do
		(
			idx = finditem MESH_NODES_4_attachPoints_arr[x][3] meshPath							
								
			if idx > 0 then --the meshPath matched
			(
				masterID = MESH_NODES_4_attachPoints_arr[x][1][1] --get the id of the matched meshPath
									
				--format "masterID: %\n" masterID
				--format "_attach_boneNumber_arr[x]: %\n" _attach_boneNumber_arr[x]
									
				--get the active bones for this meshname, use x counter
				for x2=1 to _attach_boneNumber_arr[x].count do
				(
					activeBoneID = _attach_boneNumber_arr[x][x2]
										
					--format "activeBoneID: %\n" activeBoneID
										
										
					if activeBoneID != -1 then
					(	
						--if iskindof MESH_NODES_4_attachPoints_arr[x][2][1] Editable_mesh then
						--(
							_meshNode = MESH_NODES_4_attachPoints_arr[x][2][1]
							format "_meshNode.name: %\n" _meshNode.name
							
							format "bones_array[activeBoneID].name: %\n" bones_array[activeBoneID+1].name
		
							_meshNode.transform = bones_array[activeBoneID+1].transform
							_meshNode.parent = bones_array[activeBoneID+1]
							
						--)
					)
				)
			)
		)
--*/
	
)


fn loadModel \
					count \
					data_array \
					meshPath =
(
	if (meshPath != undefined) AND \
		(pathconfig.islegalpath meshPath) AND \
		(doesfileexist meshPath) then
	(		
		g_rmv2 = meshPath
		
		bs = fopen meshPath "rb"
		---------------------------------		
			
		--clearlistener()
		--///////////////// Read Header /////////////////
		str_header = header() --create struct instance
		fill_header \
						bs \
						str_header
		str_header.meshFilePath = meshPath --add the mesh file path
		
		if str_header.headerString == "RMV2" then
		(
			--store the skeleton_type (if it exists, not all models have skeletons) in an array
-- 			if str_header.skeleton_type != undefined then
-- 			(
-- 				--Append skeleton_type_arr str_header.skeleton_type
-- 				Appendifunique skeleton_type_arr str_header.skeleton_type --!!??
-- 			)
			--TEMP just operating on one skeleton for now
			if str_header.skeleton_type != undefined then
			(
				if skeleton_type_arr.count == 0 then
				(
					Append skeleton_type_arr str_header.skeleton_type
-- 					Appendifunique skeleton_type_arr str_header.skeleton_type --!!??
				)
			)
			
			--REPORT
			--print str_header
			--///////////////////////////////////////////////
			
			
			--///////////////// Read subMesh header /////////////////
			fill_subMesh_headers \
										bs \
										data_array \
										str_header
			--//////////////////////////////////////////////////////
			
			--/* temp off
			--///////////////// Read subMesh description /////////////////			
			fill_subMeshDescription \
											bs \									
											str_header \
											count \
											data_array
			--///////////////////////////////////////////////////////////
			--*/
			
			--/* temp off
			--///////////////// Read texture paths /////////////////
			fill_geomChunk \
								bs \
								str_header \
								data_array
			--//////////////////////////////////////////////////////
			--*/
			
			--/* temp off
			--////////////// Build Mesh //////////////
			
			meshBuilder \
								data_array \								
								str_subMeshDescription
			
			--///////////////////////////////////////
			--*/
			
			---------------------------------
			fclose bs
			
			format "Done loading model: %\n" meshPath
				
			--these need to be dynamically determined
			------------------=========================================================================================
			--build paths for skeleton if it exists, and then add the bones, skin, weights etc...
-- 			if (skeleton_type_arr.count == 1) AND \
-- 				(skeleton_type_arr[1] != "" ) then
			if (skeleton_type_arr.count != 0) then
			(		
				for i=1 to skeleton_type_arr.count do
				(
					if skeleton_type_arr[i] != "" then
					(
						--Close .anim binary streams if they are open
						if (bsAN == true) then
						(
							fclose bsAn
						)
						
						--Close .bone_inv_trans_mats (matrices for bones) binary streams if they are open
						if (bsbm == true) then
						(
							fclose bsbm
						)
						----- End of close bin streams -----
						
						ext_bone_inv_trans_mats = ".bone_inv_trans_mats"
						ext_anim = ".anim"
						
						bone_inv_trans_mats = pathconfig.appendpath \
																						(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																						(skeleton_type_arr[i] + ext_bone_inv_trans_mats)

						anim = pathconfig.appendpath \
																						(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																						(skeleton_type_arr[i] + ext_anim)			
						
						if (doesfileexist bone_inv_trans_mats) AND \
							(doesfileexist anim) then
						(
							--check if the skeleton names match
							bsAn = fopen anim "rb"
							------------------------------------
								fseek bsAn 12 #seek_set
								stringLength = readshort bsAn
								skeletonName = ReadFixedString bsAn stringLength
							------------------------------------
							fclose bsAn
							
							if doesfileexist g_rmv2 then
							(
								--check if the skeleton names match
								bs_mesh = fopen g_rmv2 "rb"
								------------------------------------
									fseek bs_mesh 12 #seek_set							
									skeletonName_fromMeshFile = readstring bs_mesh
								------------------------------------
								fclose bs_mesh
								
								if skeletonName == skeletonName_fromMeshFile then
								(
									if skeletonName == skeleton_type_arr[i] AND skeletonName == str_header.skeleton_type then
									(										
										bsAn = fopen anim "rb"
										bsbm = fopen bone_inv_trans_mats "rb"			
										----------------				
											
										--/* temp off
										read_inv_trans_matrices \
																			bsbm
										--*/
										--/////////////////////// End of Inverse Transformation Matrix ///////////////////////			
										
										--/* temp off
										--read and create bones
										bones_array = read_bone_names_hierarchy \
																									bsAn
										--*/
										------------------=========================================================================================
											
										
										
										--/////////////////////// Skin and Weights ///////////////////////
													
										--/* temp off
										addSkinMod \
															mesh2_rig_animate_arr
										--*/
											--/////////////////////////////////////////////////////		
										
										--/* temp off
										addBones2Skin \
																bones_array \
																mesh2_rig_animate_arr
										--*/
										--/////////////////////////////////////////////////////
											
										--/* temp off
										set_weights \
															data_array \
															mesh2_rig_animate_arr -- for now this is always just one mesh ( I am still unsure if it can be more than one)
										--*/
										
										--//////////////////// End of Skin and Weights ////////////////////
										
										--------------------------------
										fclose bsAn
										fclose bsbm
									)
								)
							)
						)
					)
				)
				
				format "Done loading skeleton\n"
			)
		)
		else
		(
			format "Not a valid Mesh file, can't continue - cancelling!\n"
		)
	)
	
)

animation_tables_arr = #()
struct animation_tables
(
	version = "",
	
	animation_table = "", --this is the filename(without extension) of the files in ..data\animations\animation_fragments
	skeleton_type = "", --filename(without extension) of the .bone_inv_trans_mats & .anim in (this is used for the rig and bindpose) ..data\animations\skeletons
	skeleton_type_cinematic = "", --same as above but for cinematics
	
	mount_table = "", --I don't know yet what this is, will have to look into it
	
	fragment = #() --all of the fragment filename(without extension) for this animation_table
)

fn read_AnimationTables \
									fPath =
(	
	animation_tables_arr = #()
	
	--// Read Version
	fs = openfile fPath
	----------------
	str_animation_tables = animation_tables() --create an instance of the struct
	version = readline fs
	str_animation_tables.version = version
	Append animation_tables_arr str_animation_tables
	----------------
	close fs
	
	fs = openfile fPath
	----------------
	
	--start parsing
	while NOT eof fs do
	(
		str_animation_tables = animation_tables() --create an instance of the struct for "each animation_table" instance found
		struct_filled = false --but we don't want to fill the struct in case no match is made below
		
		_line = readline fs
		_lineFiltered = filterString _line " "
		if _lineFiltered[1] == "animation_table" then
		(
			struct_filled = true
			
			skipToString fs "{"
			------------------------------
			
			str_animation_tables.animation_table = _lineFiltered[2]
			
			--/*
			insideBlocks = readDelimitedString fs "}"
			
			--//----------------------------------------------------
			insideBlocksFiltered = filterString insideBlocks "\n"
	
			for s=1 to insideBlocksFiltered.count do
			(
				insideBlocksFiltered[s] = trimleft ( trimright insideBlocksFiltered[s]  "\" ")  "\" "
			)
			
			for s=1 to insideBlocksFiltered.count do
			(				
				_filter = filterstring insideBlocksFiltered[s] "\t\t"				
				
				if _filter[1] == "skeleton_type" then
				(
					str_animation_tables.skeleton_type = _filter[2]	
				)
				else if _filter[1] == "skeleton_type_cinematic" then
				(
					str_animation_tables.skeleton_type_cinematic = _filter[2]
				)
				else if _filter[1] == "mount_table" then
				(
					str_animation_tables.mount_table = _filter[2]
				)
				else if _filter[1] == "fragment" then
				(
					Append str_animation_tables.fragment _filter[2]
				)
			)
			--//----------------------------------------------------
			--*/
			
			Append animation_tables_arr str_animation_tables
		)
	)
	----------------
	close fs	
)

animation_fragments_arr = #()
struct animation_fragments
(
	--//---------------------
	version = "",
	--//---------------------
	
	
	
	--//---------------------
	skeleton_type = "", --filename(without extension) of the .bone_inv_trans_mats & .anim in (this is used for the rig and bindpose) ..data\animations\skeletons
	cinematic = "",
	--//---------------------
	
	
	
	--//---------------------
	anim_type = "",
	
	filename = "",
	
	metadata = "",
	
	blend_in_time = "",	
	weapon_bone_1 = "",
	weapon_bone_2 = "",
	weapon_bone_3 = "",
	weapon_bone_4 = ""
	--//---------------------
)

fn read_AnimationFragments \
										fPath =
(
	if fPath != undefined then
	(
		animation_fragments_arr = #()
		
		--// Read Version
		fs = openfile fPath
		
		if fs != undefined then
		(
			----------------
			str_animation_fragments = animation_fragments() --create an instance of the struct
			version = readline fs
			str_animation_fragments.version = version
			Append animation_fragments_arr str_animation_fragments
			----------------
			close fs
			
			
			fs = openfile fPath			
			----------------
			while NOT eof fs do
			(
				str_animation_fragments = animation_fragments() --create an instance of the struct
				struct_filled = false --but we don't want to fill the struct in case no match is made below
				
				_line = readline fs
				_lineFiltered = filterString _line "\t\t"
				
				if _lineFiltered[1] != undefined then
				(
					if trimleft (trimright _lineFiltered[1] "\" ") "\" " == "skeleton_type" then
					(				
						str_animation_fragments.skeleton_type = _lineFiltered[2]
						struct_filled = true
					)
					else if trimleft (trimright _lineFiltered[1] "\" ") "\" " == "cinematic" then
					(				
						str_animation_fragments.cinematic = _lineFiltered[2]
						struct_filled = true
					)
					else if ( \
									( \
										trimleft (trimright _lineFiltered[1] "\" ") "\" " != "cinematic" OR \
										trimleft (trimright _lineFiltered[1] "\" ") "\" " != "skeleton_type" OR  \
										trimleft (trimright _lineFiltered[1] "\" ") "\" " != "" \
									) \
									AND \
									( \
										(classof _lineFiltered[1] == string) \
										AND \
										(NOT matchpattern _lineFiltered[1] pattern:"*version*") \
									) \
								) then
					(
			-------------------------------------------
			-- 			anim_type = "",
						
			-- 			filename = "",
			-- 			metadata = "",
			-- 			blend_in_time = "",
			-- 			weapon_bone_1 = "",
			-- 			weapon_bone_2 = "",
			-- 			weapon_bone_3 = "",
			-- 			weapon_bone_4 = ""
			-------------------------------------------
						--if _lineFiltered.count > 2 then
						--(
						
						for x=1 to _lineFiltered.count do
						(
							struct_filled = true
							
							--// anim_type (this does not have to be filtered since it can be added as is, just some trimming needed to be sure)
							if x == 1 then
							(
								val = trimleft (trimright _lineFiltered[x] "\" ") "\" "
								str_animation_fragments.anim_type = val
							)
							--// filename
							else if x == 2 then
							(
								_filenameFilter = filterstring _lineFiltered[x] "="
								if _filenameFilter.count == 2 then
								(
									val = trimleft (trimright _filenameFilter[2] "\" ") "\" "
									str_animation_fragments.filename = val --add the value
								)
							)
							--// metadata
							else if x == 3 then
							(
								_metadataFilter = filterstring _lineFiltered[x] "="
								if _metadataFilter.count == 2 then
								(
									val = trimleft (trimright _metadataFilter[2] "\" ") "\" "
									str_animation_fragments.metadata = val --add the value
								)
							)				
							else if x == 4 then
							(
								lastLineFilter = filterstring _lineFiltered[x] ","
								
								for n=1 to lastLineFilter.count do
								(
									--blend_in_time
									if n==1 then
									(
										blend_in_timeFilter = filterstring lastLineFilter[n] "="
										if blend_in_timeFilter.count == 2 then
										(
											val = trimleft (trimright blend_in_timeFilter[2] "\" ") "\" "
											str_animation_fragments.blend_in_time = val --add the value
										)
									)
									--weapon_bone_1
									else if n==2 then
									(
										weapon_bone_1 = filterstring lastLineFilter[n] "="
										if weapon_bone_1.count == 2 then
										(
											val = trimleft (trimright weapon_bone_1[2] "\" ") "\" "
											str_animation_fragments.weapon_bone_1 = val --add the value
										)
									)
									--weapon_bone_2
									else if n==3 then
									(
										weapon_bone_2 = filterstring lastLineFilter[n] "="
										if weapon_bone_2.count == 2 then
										(
											val = trimleft (trimright weapon_bone_2[2] "\" ") "\" "
											str_animation_fragments.weapon_bone_2 = val --add the value
										)
									)
									--weapon_bone_3
									else if n==4 then
									(
										weapon_bone_3 = filterstring lastLineFilter[n] "="
										if weapon_bone_3.count == 2 then
										(
											val = trimleft (trimright weapon_bone_3[2] "\" ") "\" "
											str_animation_fragments.weapon_bone_3 = val --add the value
										)
									)
									--weapon_bone_4
									else if n==5 then
									(
										weapon_bone_4 = filterstring lastLineFilter[n] "="
										if weapon_bone_4.count == 2 then
										(
											val = trimleft (trimright weapon_bone_4[2] "\" ") "\" "
											str_animation_fragments.weapon_bone_4 = val --add the value
										)
									)
								)
							)
						)
						
						--)
					)		
					--only if the struct instance is used (match found above) do we want to append it to the array
					if struct_filled then
					(
						Append animation_fragments_arr str_animation_fragments
					)
				)
			)
			----------------
			close fs
		)
	)
)

fn create_config_array \
								fPath \
								arr =
(
	if (doesfileexist fPath) then
	(
		fs = openfile fPath	
		----------------
		while NOT eof fs do
		(
			Append arr (readline fs)
		)
		----------------
		close fs
		
		return arr;
	)
	else
	(
		return arr = #()
	)
)


fn loadAnimFromFile \
							g_rmv2 \
							rmv2anim =
(
	if (rmv2anim != undefined) AND \
		(pathConfig.isLegalPath rmv2anim) then
	(
		newAnimName = undefined	
		load_the_Anim = false
		bone_inv_trans_mats = undefined
		anim = undefined
		
		if (doesfileexist rmv2anim) then
		(
			--check if the skeleton names match
			bsAn = fopen rmv2anim "rb"
			------------------------------------
				fseek bsAn 12 #seek_set
				stringLength = readshort bsAn
				newAnimName = ReadFixedString bsAn stringLength						
			------------------------------------
			fclose bsAn
		)	
		
		--Is any mesh file at all in the scene associated with a skeleton data? returns bool
		hasSkeleton = have_Skeleton_check_rootData()
		skel_arr = #()
							
		if hasSkeleton == true then
		(
			for dx=1 to rootData[2].count do
			(
				Append skel_arr rootData[2][dx][6][1].skeleton_type
			)

			--if the new skeleton name (newAnimName) matches the one we are currently using then skelIDX will return the index
			--else it will return 0 (we are only interested in at least one match)
			skelIDX = finditem	skel_arr (getFilenameFile newAnimName)
			if skelIDX != 0 then
			(
				skeleton_type = skel_arr[skelIDX]
				
				
				
				--// Prepare the paths
				ext_bone_inv_trans_mats = ".bone_inv_trans_mats"
				ext_anim = ".anim"
								
				bone_inv_trans_mats = pathconfig.appendpath \
																				(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
																				(skeleton_type + ext_bone_inv_trans_mats)

				anim = pathconfig.appendpath \
															(getinisetting CONST_CONFIG_PATH "animations" "skeletons") \
															(skeleton_type + ext_anim)
				
				
				
				if (doesfileexist bone_inv_trans_mats) AND \
					(doesfileexist anim) then
				(
					--check if the skeleton names match
					bsAn = fopen anim "rb"
					------------------------------------
						fseek		bsAn	12 #seek_set
						stringLength			= readshort bsAn
						skeletonName			= ReadFixedString bsAn stringLength						
					------------------------------------
					fclose bsAn
				)					
										
				if newAnimName == skeletonName then
				(						 										
					load_the_Anim = true
				)
			)
		)
		
		if load_the_Anim then
		(
	 		bsAn = fopen anim "rb"
	 		bsbm = fopen bone_inv_trans_mats "rb"
			bsanim = fopen rmv2anim "rb"
			------------------------------------------
										
			restore_bindPose()
										
			----------------- restore bindPose -----------------
			--sliderTime = 0f
			--deleteKeys objects #allKeys
			frames = #()
			motionAnimBoneTable = #(#(),#())
			--the first dimension is the boneidx, the 2nd is the translation or quaternion
			_pos = #(#(),#()) --position updates (usually these are very few bones, often 1, if any) [1]=boneindex [2]=pos
			_quat = #(#(),#()) --usually ALL bones [1]=boneindex [2]=rot
			-------------------------------------------------------
			
			-- Read the keys		
			read_anim_keys \
									bsanim
			
			-- Apply the animation keys		
			inject_anim_keys \
									numFrames \
									bones_array \
									frames
				
			------------------------------------------
	 		fclose bsAn
	 		fclose bsbm
			fclose bsanim

			--rotate_models() --obsolete, now done in the UI instead

		)	
		else				
		(
			format "skeletonName: %\n" skeletonName
			format "str_header.skeleton_type: %\n" str_header.skeleton_type
			format "ERROR - Skeletons do not match, can't apply animation! (called by loadAnimFromFile())\n"
		)
	)
)




fn get_the_crests \
							rand \
							arr =
(
	c = 0
	meshCount = 0
	collectArr = #()
	
-- 	print arr._NESTED[4][1]
-- 	print arr._NESTED[4][2]
-- 	return collectArr;
	
	if arr._NESTED[1].count == 0 then
	(		
		for i=1 to arr[4][1].count do --how many numbers
		(
	-- 		format "arr._NESTED[4][1][i]: %\n" arr._NESTED[4][1][i]
			
			if arr[4][1][i] == 1 then --if we encounter 1, then we increase the iterator
			(
				c += 1		
				format "c +=: %\n" c			
				
				if (c == rand) AND \
					(i < arr[4][1].count) then --when finally the iterator is equal to the rand, then we use that index--but we only do that if we have not reached the end of the array
				(
					for x=1 to arr[4][1].count do --for all the following entries != 1 we increase the iterator meshCount
					(
						if (i+x) <= arr[4][1].count then --if we haven't reached the end of the array
						(
							if arr[4][1][i+x] != 1 then --we only continue to count up the meshCount if the integer is NOT 1
							(
								meshCount += 1
								Append collectArr arr[4][2][i+x]
							)
							else --when we encounter 1 we exit (we have gotten the meshCount and can now generate a random number between 1 and this meshCount)
							(
								return collectArr;
							)
						)
					)				
				)
			)
		)
	)
	else
	(
		for i=1 to arr._NESTED[4][1].count do --how many numbers
		(
	-- 		format "arr._NESTED[4][1][i]: %\n" arr._NESTED[4][1][i]
			
			if arr._NESTED[4][1][i] == 1 then --if we encounter 1, then we increase the iterator
			(
				c += 1		
				format "c +=: %\n" c			
				
				if (c == rand) AND \
					(i < arr._NESTED[4][1].count) then --when finally the iterator is equal to the rand, then we use that index--but we only do that if we have not reached the end of the array
				(
					for x=1 to arr._NESTED[4][1].count do --for all the following entries != 1 we increase the iterator meshCount
					(
						if (i+x) <= arr._NESTED[4][1].count then --if we haven't reached the end of the array
						(
							if arr._NESTED[4][1][i+x] != 1 then --we only continue to count up the meshCount if the integer is NOT 1
							(
								meshCount += 1
								Append collectArr arr._NESTED[4][2][i+x]
							)
							else --when we encounter 1 we exit (we have gotten the meshCount and can now generate a random number between 1 and this meshCount)
							(
								return collectArr;
							)
						)
					)				
				)
			)
		)	
	)
	
	return collectArr;
)



--//////////////////////////////// Get Decals Functions ////////////////////////////////
fn getFrom_texture_array \
									fPath =
(
	if doesfileexist fPath then
	(
		fs = openFile fPath
		-----------------------------
		links_array = #()
		
		while NOT eof fs do
		(
			Append links_array (readline fs)
		)
		-----------------------------
		close fs
		
		if links_array.count > 0 then
		(
			rand = random 1 links_array.count
			theFile = links_array[rand]
			
			--return the path to the link (remember to add the rootPath and also concatenate the desired suffix to this)
-- 			print links_array
			return theFile;
		)
	)
)

--get the relative path from the currently chosen submesh decal and prepare the paths for the texture arrays and apply them to the same struct
fn get_decalTextures \
								rand \
								arr =
(
	
	--MAP
-- 	SEPARATED_DEFS_ARR[m]._NESTED[1][11]	[rand]	[1]= diff
-- 																			[2]=normal
	
	for x=1 to arr[rand].count do --always .count = 2 for now (1= diff 2= normal) but we loop anyways
	(
		texture_array_suffix	= ".texture_array"
		dds_suffix				= ".dds"
		tga_suffix				= ".tga"
		rootPath					= getiniSetting		CONST_CONFIG_PATH		"root"		"rootpath"		
		
		_name		= arr[rand][x].decal_name		--get the name attribute
		_val			= arr[rand][x].decal_path		--get the val attribute (the relative path)
		
		if _name == "decal_diffuse" then
		(
			_finalPath = (pathConfig.appendPath rootPath _val) + texture_array_suffix			
			arr[rand][x].decal_diff_textureArray		= _finalPath		
			arr[rand][x].decal_diff_random_tex			= (pathConfig.appendPath rootPath (getFrom_texture_array		_finalPath))  + dds_suffix --the final random diff texture path
				format "arr[rand][x].decal_diff_random_tex: %\n" arr[rand][x].decal_diff_random_tex
		)
		else if _name == "decal_normal" then
		(
			_finalPath = (pathConfig.appendPath rootPath _val) + texture_array_suffix			
			arr[rand][x].decal_normal_textureArray	= _finalPath	
			arr[rand][x].decal_normal_random_tex		= (pathConfig.appendPath rootPath (getFrom_texture_array		_finalPath))  + dds_suffix --the final random normal texture path
				format "arr[rand][x].decal_diff_random_tex: %\n" arr[rand][x].decal_diff_random_tex
		)
		
		--For INFO only
		if (arr[rand][x].decal_parent != undefined) AND \
			(iskindof arr[rand][x].decal_parent array)  then
		(
			if arr[rand][x].decal_parent.count > 0 then
			(
				for n=1 to arr[rand][x].decal_parent.count do
				(
					_parent = 		arr[rand][x].decal_parent[n][1]
					
					if _parent == "name" then
					(
						_finalParent = arr[rand][x].decal_parent[n+1][1]
						
						arr[rand][x].decal_final_parent	= _finalParent
					)
				)
			)
		)
	)
	
)

--Struct to place the decal maps name and paths in (common for shields for instance)
struct decalMaps
(
	_hasDecals								= false,
	
	decal_name							= undefined, --name attrib
	decal_path								= undefined, --val attrib (which is the relative path to the texture_array)
	
	decal_parent							= undefined, --array of parent attribs variantmesh reference slot of thish mesh
	decal_final_parent					= undefined, --the final attrib name of the parent variantmesh reference slot of thish mesh
	
	decal_diff_textureArray				= undefined, --final path to the DIFFUSE texture_array
		decal_diff_random_tex			= undefined, --final random tex from the DIFFUSE texture_array
	decal_normal_textureArray			= undefined, --final path to the NORMAL texture_array
		decal_normal_random_tex		= undefined --final random tex from the NORMAL texture_array
)


fn get_meshFromNested \
											arr =
									
(		
		--for decals parent info
		decals_parent = undefined		
	
		def2_arr = #(
							#(), --the index
							#(), --path
							#(), --parentName
							#(), --parent val
							#(), --the type (ref=1, model=0)
							#(), --nested definition
							#(), --attachpoints
							#(), --sorted attachpoints
							#(),  --nested crom crests (under nested SLOT)
							#(),  --crests
							#()  --Decal Maps							
						)
	
	--Add nested
	if arr != undefined then
	(
		finArr = #()
		Append finArr (arr)		
		
		for i=1 to finArr.count do
		(
			for x=1 to finArr[i].count do
			(
				--format "%\n" definitions_array[i][x].parentIDX
				
				decals_arr				= #() --for each submesh x, all the belonging structs will be placed in this array, then it will be added to the def2_arr[11]				
				
				if finArr[i][x].parentIDX.count > 1 then
				(
					if (finArr[i][x].nodeName == "VARIANT_MESH_REFERENCE") then
					(
						for s=1 to finArr[i][x].attribs[1].count do
						(
							defMatch = stricmp finArr[i][x].attribs[1][s] "definition"
							
							if defMatch == 0 then
							(
								--Add the index for the ref node (there can be several identical numbers)
								Append def2_arr[1] finArr[i][x].parentIDX[finArr[i][x].parentIDX.count-1]
								
								--Add the path to the definition file
								Append def2_arr[2] finArr[i][x].attribs[2][s]
								
								--parentName
								Append def2_arr[3] finArr[i][x].parentName
								
								--parent val
								if x > 1 then --so that we cannot apply a non-positive index/iterator
								(
									Append def2_arr[4] finArr[i][x-1].attribs[2][s] --(note the minus one (x-1) to get to the parent)
								)
								
								--Add REF flag 1=VARIANT_MESH_REFERENCE definition		0=VARIANT_MESH model
								Append def2_arr[5] 1
							)
						)
					)
					if (finArr[i][x].nodeName == "SLOT") then
					(
						--Catch the slot name and attribs
						decals_parent = finArr[i][x].attribs
						format "................................................................................ : %\n" decals_parent

						
-- 						if (doesfileexist xmlDef_filePath2) then
-- 						(
-- 							str_read_xml2 = read_xml()
-- 							str_read_xml2.report = false
-- 							
-- 							--read definition
-- 							arr2 = str_read_xml2.main \
-- 																xmlDef_filePath2 \
-- 																str_read_xml2._xml
-- 							
-- 							

-- 							if arr2 != undefined then
-- 							(
-- 								Append 	def2_arr	(get_meshFromNested arr2)
-- 							)
-- 						)
						
						
						
						
						
-- 						for s=1 to finArr[i][x].attribs[1].count do
-- 						(
-- 							defMatch = stricmp finArr[i][x].attribs[1][s] "model"
-- 							
-- 							if defMatch == 0 then
-- 							(
-- 								--Add the index for the ref node (there can be several identical numbers)
-- 								Append def2_arr[1] finArr[i][x].parentIDX[finArr[i][x].parentIDX.count-1]
-- 								
-- 								--Add the path to the mesh
-- 								Append def2_arr[2] finArr[i][x].attribs[2][s]						
-- 								
-- 								--parentName
-- 								Append def2_arr[3] finArr[i][x].parentName
-- 								
-- 								--parent val
-- 								if x > 1 then --so that we cannot apply a non-positive index/iterator
-- 								(
-- 									Append def2_arr[4] finArr[i][x-1].attribs[2][s] --(note the minus one (x-1) to get to the parent)
-- 								)
-- 								
-- 								--Add REF flag 1=VARIANT_MESH_REFERENCE definition		0=VARIANT_MESH model
-- 								Append def2_arr[9] 0
-- 							)
-- 						)
					)
					else if (finArr[i][x].nodeName == "VARIANT_MESH") then
					(	
						for s=1 to finArr[i][x].attribs[1].count do
						(
							_name = finArr[i][x].attribs[1][s]
							
							defMatch		= stricmp _name "model"							
							decal_diffuse	= stricmp _name "decal_diffuse"
							decal_normal	= stricmp _name "decal_normal"
							
							--NOTE
							--The conditions are else if, but really, we could have case of or only if statements. But one value can never be two at once
							--so it really doesn't matter, even though logically we do not have to have else if statements. For now, I will just leave them as such
							
							if defMatch == 0 then
							(
								--Add the index for the ref node (there can be several identical numbers)
								Append def2_arr[1] finArr[i][x].parentIDX[finArr[i][x].parentIDX.count-1]
								
								--Add the path to the mesh
								Append def2_arr[2] finArr[i][x].attribs[2][s]						
								
								--parentName
								Append def2_arr[3] finArr[i][x].parentName
								
								--parent val
								if x > 1 then --so that we cannot apply a non-positive index/iterator
								(
									Append def2_arr[4] finArr[i][x-1].attribs[2][s] --(note the minus one (x-1) to get to the parent)
								)
								
								--Add REF flag 1=VARIANT_MESH_REFERENCE definition		0=VARIANT_MESH model
								Append def2_arr[5] 0
							)
							else if decal_diffuse == 0 then
							(
-- 								struct decalMaps
-- 								(
-- 									decal_name			= undefined,
-- 									decal_path				= undefined,
-- 									decal_parent		= undefined
-- 								)
								
								str_decalMaps = decalMaps() --create instance of struct
								
								str_decalMaps.decal_name			= _name --add the name to the struct
								str_decalMaps.decal_path			= finArr[i][x].attribs[2][s] --add the vanilla xml path to the struct
-- 								if x > 1 then --so that we cannot apply a non-positive index/iterator
-- 								(
									if decals_parent != undefined then
									(
										str_decalMaps.decal_parent			= decals_parent --(note the minus one (x-1) to get to the parent)	
									)
-- 								)
								
								str_decalMaps._hasDecals = true
								
								--Append		def2_arr[11]		str_decalMaps --add the struct to the array
								Append		decals_arr		str_decalMaps --add the struct to the array
							)							
							else if decal_normal == 0 then
							(
								str_decalMaps = decalMaps() --create instance of struct
								
								str_decalMaps.decal_name		= _name --add the name to the struct
								str_decalMaps.decal_path		= finArr[i][x].attribs[2][s] --add the vanilla xml path to the struct	
-- 								if x > 1 then --so that we cannot apply a non-positive index/iterator
-- 								(
									if decals_parent != undefined then
									(
										str_decalMaps.decal_parent			= decals_parent --(note the minus one (x-1) to get to the parent)	
									)
-- 								)
									
								str_decalMaps._hasDecals = true
								
								--Append		def2_arr[11]		str_decalMaps --add the struct to the array
								Append		decals_arr		str_decalMaps --add the struct to the array
							)
						)

						--/*
						------------------------------------------------------------Attach Points -------------------------------------------------------------
						attachArr = #(#(),#())
						-------------------------------------
						
						for s=1 to finArr[i][x-1].attribs[1].count do
						(
							name_match			= stricmp finArr[i][x-1].attribs[1][s] "name"
							attach_point_match	= stricmp finArr[i][x-1].attribs[1][s] "attach_point"
							
							--the attach_point attib value = the name of the bone that is to be the parent. The transformation of the mesh will be set = to the parentbone.transform (matrix)
							--example: <SLOT name="weapon_1" attach_point="weapon_01" > --the "weapon_01" is the name of bone we must set as parent to this variantmesh							
							if name_match == 0 then
							(
								for s2=1 to finArr[i][x-1].attribs[1].count do
								(
									attach_point_match2	= stricmp finArr[i][x-1].attribs[1][s2] "attach_point"
										
									if attach_point_match2 == 0 then
									(
										--attachArr = #(#(),#())-------------------
										--Appendifunique attachArr[1] nodeCounter
											
										Append attachArr[2] finArr[i][x-1].attribs[1][s] --add the name
										Append attachArr[2] finArr[i][x-1].attribs[2][s] --add the name val
										Append attachArr[2] finArr[i][x-1].attribs[1][s2] --add the attach_point
										Append attachArr[2] finArr[i][x-1].attribs[2][s2] --add the attach_point val										
									
												format "\n"
												format ".attribs[1][s]: %\n" finArr[i][x-1].attribs[1][s]
												format ".attribs[2][s]: %\n" finArr[i][x-1].attribs[2][s]										
												format ".attribs[1][s2]: %\n" finArr[i][x-1].attribs[1][s2]
												format ".attribs[2][s2]: %\n" finArr[i][x-1].attribs[2][s2]
												format "\n"
										
										---------------------------------							
										Appendifunique attachArr[1] nodeCounter
										Append def2_arr[9] attachArr
										---------------------------------------------------------------------------------------------------------------------------------------------	
									)
								)
							)						
						)						

						--*/
						
					)					
				)
				
				--Add the submesh decal set to the main array
				if decals_arr.count > 0 then
				(
					Append		def2_arr[11]		decals_arr --add the struct to the main array
				)
				
				
			)
		)		
		return def2_arr;
	)
)

fn get_varMeshRefs \
							xmlDef_filePath =
(
	
	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
	format "\n =============================  we are inside get_varMeshRefs ============================= \n"
	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
	
	
	if doesfileexist xmlDef_filePath then
	(
		str_read_xml = read_xml()
		str_read_xml.report = false
		
		--read definition
		arr = str_read_xml.main \
											xmlDef_filePath \
											str_read_xml._xml
	
		definitions_array = #()
		Append (definitions_array) (arr)
		
		--REPORT
		print arr
		
		--for decals parent info
		decals_parent = undefined
		
		/*
		for i=1 to definitions_array.count do
		(
			print definitions_array[i]
		)
		--*/
		
		--format "Get Root Path: %\n" (getinisetting CONST_CONFIG_PATH "root" "rootpath")
		
		def_arr = #(
							#(), --the index
							#(), --path
							#(), --parentName
							#(), --parent val
							#(), --the type (ref=1, model=0)
							#(), --nested definition
							#(), --attachpoints
							#(), --sorted attachpoints
							#(),  --nested crom crests (under nested SLOT)
							#(),  --crests
							#()  --Decal Maps
						)
		
		nodeCounter = 0					
		
		for i=1 to definitions_array.count do
		(
			for x=1 to definitions_array[i].count do
			(
				--format "%\n" definitions_array[i][x].parentIDX
				
				decals_arr = #() --for each submesh x, all the belonging structs will be placed in this array, then it will be added to the def2_arr[11]
				
				
				if definitions_array[i][x].parentIDX.count > 1 then
				(
					if (definitions_array[i][x].nodeName == "VARIANT_MESH_REFERENCE") then
					(						
						for s=1 to definitions_array[i][x].attribs[1].count do
						(
							defMatch = stricmp definitions_array[i][x].attribs[1][s] "definition"
							
							if defMatch == 0 then
							(
								nodeCounter += 1
								
								--Add the index for the ref node (there can be several identical numbers)
								Append def_arr[1] definitions_array[i][x].parentIDX[definitions_array[i][x].parentIDX.count-1]
								
								--Add the path
								Append def_arr[2] definitions_array[i][x].attribs[2][s]
								
								--parentName
								Append def_arr[3] definitions_array[i][x].parentName
								
								--parent val
								if x > 1 then --a guard so that we cannot apply a non-positive index/iterator
								(
									Append def_arr[4] definitions_array[i][x-1].attribs[2][s] --(note the minus one (x-1) to get to the parent)
								)
								
								--Add REF flag 1=VARIANT_MESH_REFERENCE definition		0=VARIANT_MESH model
								Append def_arr[5] 1
							)
						)
						
						------------------------------------------------------------Attach Points -------------------------------------------------------------
						attachArr = #(#(),#())
						---------------------------------
						
						if (definitions_array[i][x-1].nodeName == "SLOT") then --get the attachpoints
						(
							for s=1 to definitions_array[i][x-1].attribs[1].count do
							(
								name_match			= stricmp definitions_array[i][x-1].attribs[1][s] "name"
								attach_point_match	= stricmp definitions_array[i][x-1].attribs[1][s] "attach_point"
							
								--the attach_point attib value = the name of the bone that is to be the parent. The transformation of the mesh will be set = to the parentbone.transform (matrix)
								--example: <SLOT name="weapon_1" attach_point="weapon_01" > --the "weapon_01" is the name of bone we must set as parent to this variantmesh							
								if name_match == 0 then
								(
									for s2=1 to definitions_array[i][x-1].attribs[1].count do
									(
										attach_point_match2	= stricmp definitions_array[i][x-1].attribs[1][s2] "attach_point"
										
										if attach_point_match2 == 0 then
										(
											--attachArr = #(#(),#())-------------------
											--Appendifunique attachArr[1] nodeCounter
											
											Append attachArr[2] definitions_array[i][x-1].attribs[1][s] --add the name
											Append attachArr[2] definitions_array[i][x-1].attribs[2][s] --add the name val
											Append attachArr[2] definitions_array[i][x-1].attribs[1][s2] --add the attach_point
											Append attachArr[2] definitions_array[i][x-1].attribs[2][s2] --add the attach_point val										
									
													format "\n"
													format ".attribs[1][s]: %\n" definitions_array[i][x-1].attribs[1][s]
													format ".attribs[2][s]: %\n" definitions_array[i][x-1].attribs[2][s]										
													format ".attribs[1][s2]: %\n" definitions_array[i][x-1].attribs[1][s2]
													format ".attribs[2][s2]: %\n" definitions_array[i][x-1].attribs[2][s2]
													format "\n"
												

										)
									)
								)						
							)
						)
						if nodeCounter > 0 then
						(
							---------------------------------							
							Appendifunique attachArr[1] nodeCounter
							Append def_arr[7] attachArr
						)
						---------------------------------------------------------------------------------------------------------------------------------------------

					)
					else if (definitions_array[i][x].nodeName == "SLOT") then
					(
						--Catch the slot name and attribs
						decals_parent = definitions_array[i][x].attribs
						format "................................................................................ : %\n" decals_parent
						
					)
					else if (definitions_array[i][x].nodeName == "VARIANT_MESH") then
					(						
						for s=1 to definitions_array[i][x].attribs[1].count do
						(
							_name					= definitions_array[i][x].attribs[1][s]
							
							defMatch				= stricmp _name "model"
							decal_diffuse		= stricmp _name"decal_diffuse"
							decal_normal		= stricmp _name "decal_normal"
							
							--The conditions are else if, but really, we could have case of or only if statements. But one value can never be two at once
							--so it really doesn't matter, even though logically we do not have to have else if statements. For now, I will just leave them as such
							
							if defMatch == 0 then
							(
								nodeCounter += 1
								
								--Add the index for the ref node (there can be several identical numbers)
								Append def_arr[1] definitions_array[i][x].parentIDX[definitions_array[i][x].parentIDX.count-1]
								
								--Add the path
								Append def_arr[2] definitions_array[i][x].attribs[2][s]						
								
								--parentName
								Append def_arr[3] definitions_array[i][x].parentName
								--parent val
								if x > 1 then --so that we cannot apply a non-positive index/iterator
								(
									Append def_arr[4] definitions_array[i][x-1].attribs[2][s] --(note the minus one (x-1) to get to the parent)
								)
								
								--Add REF flag 1=VARIANT_MESH_REFERENCE definition		0=VARIANT_MESH model
								Append def_arr[5] 0
							)
							else if decal_diffuse == 0 then
							(
-- 								struct decalMaps
-- 								(
-- 									decal_name			= undefined,
-- 									decal_path				= undefined,
-- 									decal_parent		= undefined
-- 								)
								
								str_decalMaps = decalMaps() --create instance of struct
								
								str_decalMaps.decal_name	= _name --add the name to the struct
								str_decalMaps.decal_path		= definitions_array[i][x].attribs[2][s] --add the vanilla xml path to the struct								
-- 								if x > 1 then --so that we cannot apply a non-positive index/iterator
-- 								(
									if decals_parent != undefined then
									(
										str_decalMaps.decal_parent			= decals_parent --(note the minus one (x-1) to get to the parent)	
									)
-- 								)
								
								--Append		def2_arr[11]		str_decalMaps --add the struct to the array
								Append		decals_arr		str_decalMaps --add the struct to the array
							)							
							else if decal_normal == 0 then
							(
								str_decalMaps = decalMaps() --create instance of struct
								
								str_decalMaps.decal_name	= _name --add the name to the struct
								str_decalMaps.decal_path		= definitions_array[i][x].attribs[2][s] --add the vanilla xml path to the struct
-- 								if x > 1 then --so that we cannot apply a non-positive index/iterator
-- 								(
									if decals_parent != undefined then
									(
										str_decalMaps.decal_parent			= decals_parent --(note the minus one (x-1) to get to the parent)	
									)
-- 								)
								
								--Append		def2_arr[11]		str_decalMaps --add the struct to the array
								Append		decals_arr		str_decalMaps --add the struct to the array
							)
						)						
						
						------------------------------------------------------------Attach Points -------------------------------------------------------------
						attachArr = #(#(),#())
						---------------------------------
						
						if (definitions_array[i][x-1].nodeName == "SLOT") then --get the attachpoints
						(
							for s=1 to definitions_array[i][x-1].attribs[1].count do
							(
								name_match			= stricmp definitions_array[i][x-1].attribs[1][s] "name"
								attach_point_match	= stricmp definitions_array[i][x-1].attribs[1][s] "attach_point"
							
								--the attach_point attib value = the name of the bone that is to be the parent. The transformation of the mesh will be set = to the parentbone.transform (matrix)
								--example: <SLOT name="weapon_1" attach_point="weapon_01" > --the "weapon_01" is the name of bone we must set as parent to this variantmesh							
								if name_match == 0 then
								(
									for s2=1 to definitions_array[i][x-1].attribs[1].count do
									(
										attach_point_match2	= stricmp definitions_array[i][x-1].attribs[1][s2] "attach_point"
										
										if attach_point_match2 == 0 then
										(
											--attachArr = #(#(),#())-------------------
											--Appendifunique attachArr[1] nodeCounter
											
											Append attachArr[2] definitions_array[i][x-1].attribs[1][s] --add the name
											Append attachArr[2] definitions_array[i][x-1].attribs[2][s] --add the name val
											Append attachArr[2] definitions_array[i][x-1].attribs[1][s2] --add the attach_point
											Append attachArr[2] definitions_array[i][x-1].attribs[2][s2] --add the attach_point val										
									
													format "\n"
													format ".attribs[1][s]: %\n" definitions_array[i][x-1].attribs[1][s]
													format ".attribs[2][s]: %\n" definitions_array[i][x-1].attribs[2][s]										
													format ".attribs[1][s2]: %\n" definitions_array[i][x-1].attribs[1][s2]
													format ".attribs[2][s2]: %\n" definitions_array[i][x-1].attribs[2][s2]
													format "\n"												

										)
									)
								)						
							)
						)						
						
						
						if nodeCounter > 0 then
						(
							---------------------------------							
							Appendifunique attachArr[1] nodeCounter
							Append def_arr[7] attachArr
						)
						---------------------------------------------------------------------------------------------------------------------------------------------		
					)
				)
				
				
			
			--Add the submesh decal set to the main array
			if decals_arr.count > 0 then
			(
				Append		def2_arr[11]		decals_arr --add the struct to the main array
			)
			
			
				
			)			
		)
		
		---------------	---------------	---------------	---------------	---------------	---------------	---------------
		format "def_arr (BEFORE attach point sorting):\n"
		print def_arr
		---------------	---------------	---------------	---------------	---------------	---------------	---------------
		
		--sort the attach points
		for x=1 to def_arr[1].count do
		(
			--if x == def_arr[7][x][1][1] then
			--(
				Append def_arr[8] def_arr[7][x][2]					
			--)			
		)
		def_arr[7] = #()
		
		---------------	---------------	---------------	---------------	---------------	---------------	---------------
		format "def_arr (AFTER attach point sorting):\n"
		print def_arr
		---------------	---------------	---------------	---------------	---------------	---------------	---------------
		
		
		--Separate the paths into groups belonging to the same SLOT node
		unique = #()
		for u=1 to def_arr[1].count do
		(
			Appendifunique unique def_arr[1][u]			
		)
		
		---------------	---------------	---------------	---------------	---------------	---------------	---------------
		format "unique = #():\n"
		for i in unique do print i
		---------------	---------------	---------------	---------------	---------------	---------------	---------------
		
		for u=1 to unique.count do
		(
			format "u: %\n" u
			
			str_sorted_varMeshRef = sorted_varMeshRef() --create instance, only equal to the sum of unique SLOTS
			
			for x=1 to def_arr[1].count do
			(
				if (def_arr[1][x] == unique[u]) AND \
					(def_arr[5][x] == 1)  then ---------------------if variant refs---------------------
				(
					--format "________VARIANT_MESH_REFERENCE________\n"
					--format "%\n" def_arr[2][x]
					
					str_sorted_varMeshRef._type	=	def_arr[5][x]
						Append 		str_sorted_varMeshRef._separated_paths		def_arr[2][x]
						Append 		str_sorted_varMeshRef._parentName			def_arr[3][x]
						Append 		str_sorted_varMeshRef._parentVal				def_arr[4][x]
					
						--skip empty arrays
						if def_arr[8][x].count > 0 then
						(
							Append 		str_sorted_varMeshRef._attach_points			def_arr[8][x]  --add the attach points
						)
						
					--/*
					--///////////////// Process the NESTED    VARIANT_MESH_REFERENCE files /////////////////
					rootPath = getinisetting CONST_CONFIG_PATH "root" "rootpath"
					xmlDef_filePath2 = pathconfig.appendpath rootPath def_arr[2][x]
					
					if (doesfileexist xmlDef_filePath2) then
					(
						str_read_xml2 = read_xml()
						str_read_xml2.report = false
						
						--read definition
						nested_arr = str_read_xml2.main \
																	xmlDef_filePath2 \
																	str_read_xml2._xml
						
						

						if nested_arr != undefined then
						(
							Append			str_sorted_varMeshRef._NESTED			(get_meshFromNested		nested_arr)
						)
					)
					--////////////// End of Process the NESTED    VARIANT_MESH_REFERENCE files //////////////
					--*/					
					
				)
				else if (def_arr[1][x] == unique[u]) AND \
							(def_arr[5][x] == 0)  then ---------------------if meshes---------------------
				(
					format "________MESH________\n"
					
					str_sorted_varMeshRef._type	=	def_arr[5][x]
						Append 		str_sorted_varMeshRef._separated_paths		def_arr[2][x]
						Append 		str_sorted_varMeshRef._parentName			def_arr[3][x]
						Append 		str_sorted_varMeshRef._parentVal				def_arr[4][x]
					
						--skip empty arrays
						if def_arr[8][x].count > 0 then
						(
							Append 		str_sorted_varMeshRef._attach_points			def_arr[8][x]  --add the attach points
						)
				)
			)
			
			---------------	---------------	---------------	---------------	---------------	---------------	---------------
			format "\n\n str_sorted_varMeshRef: ------------:\n"---------------------
			print str_sorted_varMeshRef._separated_paths
			---------------	---------------	---------------	---------------	---------------	---------------	---------------			
			
			if str_sorted_varMeshRef._type != undefined then --WE DO NOT WANT TO ADD THE STRUCT IF NO MATCH WAS FOUND
			(				
				Append SEPARATED_DEFS_ARR str_sorted_varMeshRef
			)			
			
			---------------	---------------	---------------	---------------	---------------	---------------	---------------
			format "\n\n SEPARATED_DEFS_ARR[1]._NESTED.count: ------------:\n"---------------------
			print SEPARATED_DEFS_ARR[1]._NESTED.count
			---------------	---------------	---------------	---------------	---------------	---------------	---------------
		)
		
		--print SEPARATED_DEFS_ARR.count
		--for i in SEPARATED_DEFS_ARR do print i
		
		
-- 		struct sorted_varMeshRef
-- 		(
-- 			_type						= undefined,
-- 			_idx						= #(),
-- 			_raw_paths				= #(),
-- 			_separated_paths		= #(),
-- 			_parentName				= #(),
-- 			_parentVal				= #(),
	
-- 			_NESTED					= #(),
-- 			
-- 			_random					= "",
-- 			_random_crest			= "",
-- 			
-- 			_attach_points			= #(),
-- 			_attach_crests			= #()
-- 		)
		
		for i=1 to SEPARATED_DEFS_ARR.count do
		(			
			
			---------------	---------------	---------------	---------------	---------------	---------------	---------------
			format "\n\n SEPARATED_DEFS_ARR[i]: ------------:\n"
			print SEPARATED_DEFS_ARR[i]
			
			format "\n\n SEPARATED_DEFS_ARR[i]._separated_paths.count: ------------:\n"
			print SEPARATED_DEFS_ARR[i]._separated_paths.count
			
			format "\n\n SEPARATED_DEFS_ARR[i]._NESTED.count : ------------:\n"
			print SEPARATED_DEFS_ARR[i]._NESTED.count 			
			---------------	---------------	---------------	---------------	---------------	---------------	---------------
			
			
			if (SEPARATED_DEFS_ARR[i]._separated_paths.count == 1) then -------------temp dirty HACK (if only one variant)
			(				
				--nothing nested, so apply the path to the mesh here
				_random = random 1 SEPARATED_DEFS_ARR[i]._separated_paths.count
				SEPARATED_DEFS_ARR[i]._random = SEPARATED_DEFS_ARR[i]._separated_paths[1]
				
				if /*new start*/(SEPARATED_DEFS_ARR[i]._NESTED.count == 1) AND/*new end*/  \
									(SEPARATED_DEFS_ARR[i]._NESTED[1].count == 0) then
				(				
					--Helmets Crests Attach Points
					if (SEPARATED_DEFS_ARR[i]._parentVal[1] == "helmets") then
					(
						format "---------------------------------- We are inside CRESTS -------------------------------------\n"
							
						crest_arr = get_the_crests \
																	_random \
																	SEPARATED_DEFS_ARR[i]
						if crest_arr.count > 0 then
						(
							_rand = random 1 crest_arr.count
							SEPARATED_DEFS_ARR[i]._randInt_crest = _rand --store the _random integer
								
							SEPARATED_DEFS_ARR[i]._random_crest = crest_arr[_rand] --add the random rigid mesh
								
							format "SEPARATED_DEFS_ARR[i]._random_crest: %\n"			SEPARATED_DEFS_ARR[i]._random_crest
							format "SEPARATED_DEFS_ARR[i]._randInt_crest: %\n"			SEPARATED_DEFS_ARR[i]._randInt_crest
						)
					)
					--Decals
					else if SEPARATED_DEFS_ARR[i]._parentVal[1] == "shield" then
					(
						format "---------------------------------- We are inside SHIELD 0 -------------------------------------\n"
						
						--The functions below work only for subs, we need to implement a function or method for Master Meshes
-- 						get_decalTextures \
-- 													_random \
-- 													SEPARATED_DEFS_ARR[i][1][11]
-- 						
-- 						SEPARATED_DEFS_ARR[i]._hasDecals		= true
					)
				)
				
				--only 1 variantmeshdefinition nested
				if (SEPARATED_DEFS_ARR[i]._NESTED.count >= 1) AND \
					(SEPARATED_DEFS_ARR[i]._separated_paths.count >= 1) then --(we must have >= here !!!)
				(
						_random = random 1 SEPARATED_DEFS_ARR[i]._NESTED[1][5].count
							SEPARATED_DEFS_ARR[i]._randInt = _random --store the _random integer
						
					SEPARATED_DEFS_ARR[i]._random = SEPARATED_DEFS_ARR[i]._NESTED[1][2][_random] --add the random rigid mesh - separated paths is just 1 here !! (below it is more than 1!)
					
							format "----------------------------\n\n"
								format "SEPARATED_DEFS_ARR[i]._type: %\n" 						SEPARATED_DEFS_ARR[i]._type
								format "SEPARATED_DEFS_ARR[i]._idx: %\n" 						SEPARATED_DEFS_ARR[i]._idx
								format "SEPARATED_DEFS_ARR[i]._separated_paths: %\n" 		SEPARATED_DEFS_ARR[i]._separated_paths
								format "SEPARATED_DEFS_ARR[i]._parentName: %\n" 			SEPARATED_DEFS_ARR[i]._parentName
								format "SEPARATED_DEFS_ARR[i]._parentVal: %\n" 				SEPARATED_DEFS_ARR[i]._parentVal
								format "SEPARATED_DEFS_ARR[i]._NESTED: %\n" 					SEPARATED_DEFS_ARR[i]._NESTED
									format "SEPARATED_DEFS_ARR[i]._NESTED[1][5]: %\n" 			SEPARATED_DEFS_ARR[i]._NESTED[1][5]
									format "SEPARATED_DEFS_ARR[i]._NESTED[1][11]: %\n" 			SEPARATED_DEFS_ARR[i]._NESTED[1][11]
								format "SEPARATED_DEFS_ARR[i]._random: %\n"					SEPARATED_DEFS_ARR[i]._random
								format "SEPARATED_DEFS_ARR[i]._randInt: %\n"					SEPARATED_DEFS_ARR[i]._randInt
								format "SEPARATED_DEFS_ARR[i]._attach_points: %\n"			SEPARATED_DEFS_ARR[i]._attach_points
								format "SEPARATED_DEFS_ARR[i]._decalMaps: %\n"				SEPARATED_DEFS_ARR[i]._decalMaps
							format "----------------------------\n\n"
					
					
					--Helmets Crests Attach Points
					if (SEPARATED_DEFS_ARR[i]._NESTED[1].count > 1) AND \ -- we use > 1 because if it is only one, then the only random choice can be only that one!
						(SEPARATED_DEFS_ARR[i]._parentVal[1] == "helmets") then
					(
						format "---------------------------------- We are inside CRESTS -------------------------------------\n"
						
						crest_arr = get_the_crests \
																_random \
																SEPARATED_DEFS_ARR[i]
						if crest_arr.count > 0 then
						(
							_rand = random 1 crest_arr.count
								SEPARATED_DEFS_ARR[i]._randInt_crest = _rand --store the _random integer
							
							SEPARATED_DEFS_ARR[i]._random_crest = crest_arr[_rand] --add the random rigid mesh
							
							format "SEPARATED_DEFS_ARR[i]._random_crest: %\n"			SEPARATED_DEFS_ARR[i]._random_crest
							format "SEPARATED_DEFS_ARR[i]._randInt_crest: %\n"			SEPARATED_DEFS_ARR[i]._randInt_crest
						)
					)
					--Decals
					else if (SEPARATED_DEFS_ARR[i]._NESTED[1].count > 1) AND \ -- we use > 1 because if it is only one, then the only random choice can be only that one!
						(SEPARATED_DEFS_ARR[i]._parentVal[1] == "shield") then
					(
						format "---------------------------------- We are inside SHIELD 1 -------------------------------------\n"
						
						get_decalTextures \
													_random \
													SEPARATED_DEFS_ARR[i]._NESTED[1][11]
						
						SEPARATED_DEFS_ARR[i]._subsHaveDecals		= true
					)
				)
			)			
			else if (SEPARATED_DEFS_ARR[i]._NESTED.count >= 1) AND \
						(SEPARATED_DEFS_ARR[i]._separated_paths.count > 1) then  -------------several variantmeshdefinition nested
			(
				
				_random = random 1 SEPARATED_DEFS_ARR[i]._NESTED[1][5].count
					SEPARATED_DEFS_ARR[i]._randInt = _random --store the _random integer
				
				SEPARATED_DEFS_ARR[i]._random = SEPARATED_DEFS_ARR[i]._NESTED[1][2][_random] --add the random rigid mesh

				format "----------------------------\n\n"
					format "SEPARATED_DEFS_ARR[i]._type: %\n" 						SEPARATED_DEFS_ARR[i]._type
					format "SEPARATED_DEFS_ARR[i]._idx: %\n" 						SEPARATED_DEFS_ARR[i]._idx
					format "SEPARATED_DEFS_ARR[i]._separated_paths: %\n" 		SEPARATED_DEFS_ARR[i]._separated_paths
					format "SEPARATED_DEFS_ARR[i]._parentName: %\n" 			SEPARATED_DEFS_ARR[i]._parentName
					format "SEPARATED_DEFS_ARR[i]._parentVal: %\n" 				SEPARATED_DEFS_ARR[i]._parentVal
					format "SEPARATED_DEFS_ARR[i]._NESTED: %\n" 					SEPARATED_DEFS_ARR[i]._NESTED
						format "SEPARATED_DEFS_ARR[i]._NESTED[1][5]: %\n" 			SEPARATED_DEFS_ARR[i]._NESTED[1][5]
						format "SEPARATED_DEFS_ARR[i]._NESTED[1][11]: %\n" 			SEPARATED_DEFS_ARR[i]._NESTED[1][11]
					format "SEPARATED_DEFS_ARR[i]._random: %\n"					SEPARATED_DEFS_ARR[i]._random
					format "SEPARATED_DEFS_ARR[i]._randInt: %\n"					SEPARATED_DEFS_ARR[i]._randInt
					format "SEPARATED_DEFS_ARR[i]._attach_points: %\n"			SEPARATED_DEFS_ARR[i]._attach_points
						format "SEPARATED_DEFS_ARR[i]._decalMaps: %\n"				SEPARATED_DEFS_ARR[i]._decalMaps
					format "_random__________________________________________________________________________________: %\n" _random
				
					--Helmets Crests Attach Points
					if (SEPARATED_DEFS_ARR[i]._NESTED[1].count > 1) AND \
						(SEPARATED_DEFS_ARR[i]._parentVal[1] == "helmets") then
					(
						format "---------------------------------- We are inside CRESTS -------------------------------------\n"
						
						crest_arr = get_the_crests \
																_random \
																SEPARATED_DEFS_ARR[i]
						if crest_arr.count > 0 then
						(
							_rand = random 1 crest_arr.count
								SEPARATED_DEFS_ARR[i]._randInt_crest = _rand --store the _random integer
							
							SEPARATED_DEFS_ARR[i]._random_crest = crest_arr[_rand] --add the random rigid mesh
							
							format "SEPARATED_DEFS_ARR[i]._random_crest: %\n"			SEPARATED_DEFS_ARR[i]._random_crest
							format "SEPARATED_DEFS_ARR[i]._randInt_crest: %\n"			SEPARATED_DEFS_ARR[i]._randInt_crest
						)
					)
					--Decals
					else if (SEPARATED_DEFS_ARR[i]._NESTED[1].count > 1) AND \
						(SEPARATED_DEFS_ARR[i]._parentVal[1] == "shield") then
					(
						format "---------------------------------- We are inside SHIELD 2 -------------------------------------\n"
						
						get_decalTextures \
													_random \
													SEPARATED_DEFS_ARR[i]._NESTED[1][11]
						
						SEPARATED_DEFS_ARR[i]._subsHaveDecals		= true
					)
					
				format "----------------------------\n\n"				
			)
			--multiple meshes but nothing nested
			else if (SEPARATED_DEFS_ARR[i]._separated_paths.count >= 1) AND \
						(SEPARATED_DEFS_ARR[i]._NESTED.count == 0) then -------------temp dirty HACK (if only one variant)
			(
				--nothing nested, so apply the path to the mesh here
				_random = random 1 SEPARATED_DEFS_ARR[i]._separated_paths.count
				SEPARATED_DEFS_ARR[i]._random = SEPARATED_DEFS_ARR[i]._separated_paths[1]
			)
			else
			(
				---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
				format "\n\n +++++++++++++++++++++ NO OPERATION DONE IN HERE +++++++++++++++++++++ \n"			
				---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
			)
		)		
	)
	else
	(
		format "ERROR - Can't find file: %\n" (xmlDef_filePath as string)
	)	
)


fn get_the_RANDOM_meshes =
(	
	root_path = getinisetting CONST_CONFIG_PATH "root" "rootpath"
	
	for i=1 to SEPARATED_DEFS_ARR.count do
	(
		--add randoms
		if (SEPARATED_DEFS_ARR[i]._random != undefined AND SEPARATED_DEFS_ARR[i]._random != "") AND \
			(pathconfig.islegalpath SEPARATED_DEFS_ARR[i]._random) then
		(
			finalPath = pathConfig.appendpath root_path SEPARATED_DEFS_ARR[i]._random
			if doesfileexist finalPath then
			(
				Append rootData[1] finalPath
			)			
		)
		
		--add the crest/helmets random
		if (SEPARATED_DEFS_ARR[i]._random_crest != undefined AND SEPARATED_DEFS_ARR[i]._random_crest != "") AND \
			(pathconfig.islegalpath SEPARATED_DEFS_ARR[i]._random_crest) then
		(
			finalPath = pathConfig.appendpath root_path SEPARATED_DEFS_ARR[i]._random_crest
			if doesfileexist finalPath then
			(
				Append rootData[1] finalPath
			)			
		)
	)
	format "----------------------------\n\n"
	Append rootData[3] SEPARATED_DEFS_ARR
	return rootData;
)


fn confirm_correct_skeleton \
										mesh_file \
										anim_file =
(
	
	skeletonName									= ""
	skeletonName_fromMeshFile_game		= ""	
	skeletonName_fromMeshFile				= ""
	
	--check if the skeleton names match
	bsAn = fopen anim_file "rb"
	------------------------------------
		fseek bsAn 12 #seek_set
		stringLength = readshort bsAn
			skeletonName = ReadFixedString bsAn stringLength --get the skeleton name for the anim file
	------------------------------------
	fclose bsAn				
				
	
	
	--check if the skeleton names match
	bs_mesh = fopen mesh_file "rb"
	------------------------------------
	fseek bs_mesh 12 #seek_set							
		
		skeletonName_fromMeshFile = readstring bs_mesh --get the skeleton name from the mesh file
		
	if skeletonName_fromMeshFile != undefined then
	(
		skeletonName_fromMeshFile_game = (skeletonName_fromMeshFile + "_game")
	)
	else
	(
		skeletonName_fromMeshFile_game = ""
	)
	------------------------------------
	fclose bs_mesh
	
	
	
	if (skeletonName == skeletonName_fromMeshFile) OR \
		(skeletonName == skeletonName_fromMeshFile_game) then
	(
		return true;
	)
	else
	(
		return false;
	)
)








--/////////////////// Check for Decals runtime ///////////////////
--The global array
decals_targets_arr = #()

--The struct definition
struct decals_targets
(
	rigidMeshFile					= "",
	tgt_hasDecals					= 0,
	tgt_subsHaveDecals		= 0,
	_randInt							= 0,
	
	originalIDX						= 0,
	rootData2IDX					= 0
)

--The function
fn check_if_meshFile_has_decals \
												fPath =
(
	str_decals_targets = decals_targets()
	
	fPath_fileName = filenameFromPath fPath --get the filename of the mesh
	
	for n=1 to SEPARATED_DEFS_ARR.count do
	(		
		--we don't have to check for undefined, because the default string is ""
		_random_fileName = filenameFromPath SEPARATED_DEFS_ARR[n]._random	 --get the filename of the random mesh

		if fPath_fileName == _random_fileName then --first we must check if the random mesh name matches the one we are trying to check, if not, then there is no point in proceeding
		(
			for n2=1 to rootData[2] .count do
			(
				str_decals_targets = decals_targets() --create struct instance
					
				meshFileName = filenameFromPath rootData[2][n2][6][1].meshFilePath
				format "meshFileName: %		fPath_fileName: %\n" meshFileName fPath_fileName
					
				if meshfileName == fPath_fileName then
				(	
					if (SEPARATED_DEFS_ARR[n]._hasDecals != undefined) AND \
						(SEPARATED_DEFS_ARR[n]._hasDecals) then
					(
						str_decals_targets.rigidMeshFile						= fPath
						str_decals_targets.tgt_hasDecals					= true
						str_decals_targets._randInt							= SEPARATED_DEFS_ARR[n]._randInt --get the random integer
						
						str_decals_targets.rootData2IDX					= n2
						str_decals_targets.originalIDX						= n
						
						Append decals_targets_arr str_decals_targets	
					)
												
					if (SEPARATED_DEFS_ARR[n]._subsHaveDecals != undefined) AND \
						(SEPARATED_DEFS_ARR[n]._subsHaveDecals) then
					(
						str_decals_targets.rigidMeshFile						= fPath
						str_decals_targets.tgt_subsHaveDecals			= true
						str_decals_targets._randInt							= SEPARATED_DEFS_ARR[n]._randInt --get the random integer
						
						str_decals_targets.rootData2IDX					= n2
						str_decals_targets.originalIDX						= n
						
						Append decals_targets_arr str_decals_targets	
					)	
				)
			)						
		)
	)
	
	return decals_targets_arr;
)
--/////////////////// End of Check for Decals runtime ///////////////////

--/////////////////// Apply decal textures runtime (to be run inside the set_material function  ///////////////////
fn apply_decalTextures_runtime \
											n \
											obj =
(
	for i=1 to decals_targets_arr.count do
	(
		if (decals_targets_arr[i].tgt_subsHaveDecals) AND \
			(decals_targets_arr[i].rootData2IDX == n) then
		(				
			origIDX	= decals_targets_arr[i].originalIDX
			_rand			= decals_targets_arr[i]._randInt
				
			for x=1 to rootData[3][1][origIDX]._NESTED[1][11][_rand].count do
			(					
				decalStruct =  rootData[3][1][origIDX]._NESTED[1][11][_rand][x]
					
				if decalStruct._hasDecals then
				(
					decal_name = decalStruct.decal_name
						
					if decal_name == "decal_diffuse" then
					(							
						if doesfileexist decalStruct.decal_diff_random_tex then
						(	
							obj.mat.diffusemap.maplist.count = 2						
							nMaps = obj.mat.diffusemap.maplist.count								
								
							--set diffusemap
							obj.mat.diffusemap.maplist[nMaps] = Bitmaptexture filename:decalStruct.decal_diff_random_tex
								
									found_and_applied_atLeast_1_tex = true
								
							--------------------------------- UVW clip ---------------------------------
							obj.mat.diffusemap.maplist[nMaps].apply				= on
							obj.mat.diffusemap.maplist[nMaps].cropPlace		= 1
							obj.mat.diffusemap.maplist[nMaps].useJitter			= off
								
							obj.mat.diffusemap.maplist[nMaps].clipu				= 0.32
							obj.mat.diffusemap.maplist[nMaps].clipv				= 0.32								
							obj.mat.diffusemap.maplist[nMaps].cliph				= 0.638
							obj.mat.diffusemap.maplist[nMaps].clipw				= 0.638
							-------------------------------------------------------------------------------
								
							--set blendmode
							--obj.mat.diffusemap.blendMode[nMaps] = 14 --overlay
								
							--Do an inner loop for the normal map
							for x=1 to rootData[3][1][origIDX]._NESTED[1][11][_rand].count do
							(					
								decalStruct =  rootData[3][1][origIDX]._NESTED[1][11][_rand][x]
									
								if decalStruct._hasDecals then
								(
									if decal_name == "decal_normal" then
									(
										if doesfileexist decalStruct.decal_normal_random_tex then
										(
											--Add code for the normal map here (the line below is copied from the diffuse)
											--obj.mat.diffusemap.maplist[nMaps] = Bitmaptexture filename:decalStruct.decalStruct.decal_diff_random_tex 
										)
									)
								)
							)								
						)
						else
						(
							obj.mat.diffusemap.maplist.count -= 1
						)
					)
				)
			)
		)
	)
)
--//////////////// End of Apply decal textures runtime (to be run inside the set_material function  ////////////////
--------------------------------------

--to be run inside the function set_material()
fn apply_textures \
							obj \
							type \
							tex =
(
	
	format "------------------we are inside apply_textures-------------------- \n" ---------
	
	--texture type flags
	-- 0 = diffuse
	-- 1 = normal
	-- 11 = specular
	-- 3 = mask
	-- 12 = glossiness	
	
	rootPath					= getiniSetting		CONST_CONFIG_PATH		"root"		"rootpath"		
	
	
	if (rootPath != undefined) AND \	
		(pathConfig.islegalpath rootPath) then
	(
		if (type != undefined) AND \
			(tex != undefined ) then
		(			
			local texPath = pathConfig.appendPath		rootPath			tex --construct the final texture path
			
			if obj != undefined then
			(								
				if (doesfileexist texPath) then
				(								
					case of
					(
						--// Diffuse
						(type == 0x00): \
						(						
							------------------- New for composite ----------------------										
							obj.mat.diffuseMap.maplist[1]		= Bitmaptexture filename:texPath													
												
							--Add diffuse to mask slot
							obj.mat.diffuseMap.mask[1]		= Bitmaptexture filename:texPath
							obj.mat.diffuseMap.mask[1].alphaSource = 0
							obj.mat.diffuseMap.mask[1].monoOutput = 1
							obj.mat.diffuseMap.maskEnabled[1] = off
							---------------------------------------------------------------
												
												
							--obj.mat.diffusemap = Bitmaptexture filename:texPath --replaced with composite				
							--obj.mat.showInViewport = on --show map in viewport
												
							obj.mat.opacityMap = Bitmaptexture filename:texPath
							obj.mat.opacityMap.alphaSource = 0
							obj.mat.opacityMap.monoOutput = 1
						) --diffuse
											
						--// Normal
						(type == 0x01): \
						(
							if obj.mat.bumpmap == undefined then
							(
								obj.mat.bumpmap = Normal_bump()
							)
							obj.mat.bumpmap.normal_map = Bitmaptexture filename:texPath
							obj.mat.bumpmap.normal_map.alphasource = 2
						) --normal
										
						--// Specular
						(type == 0x0B): \
						(
							obj.mat.specularLevelMap = Bitmaptexture filename:texPath
							obj.mat.specularLevelMap.alphasource = 2
						)
											
						--// Opacity / Mask Test (?)
						(type == 0x03): \
						(
							------------------------------------------------------------------------------------------------------
							obj.mat.diffuseMap.mask[1]		= Bitmaptexture filename:texPath										
											
							obj.mat.diffuseMap.mask[1].alphaSource = 0
							obj.mat.diffuseMap.mask[1].monoOutput = 1
								obj.mat.diffuseMap.maskEnabled[1] = off
							------------------------------------------------------------------------------------------------------
												
		-- 	 				obj.mat.opacityMap = Bitmaptexture filename:texPath
		-- 					obj.mat.opacityMap.alphaSource = 0
		-- 					obj.mat.opacityMap.monoOutput = 1
												
							--Temp report
							print "Opacity type Texture flag found"
						)
											
						--// Mask Regular (?)
						(type == 0x0A): \
						(
			-- 				obj.mat.opacityMap = Bitmaptexture filename:texPath
			-- 				obj.mat.opacityMap.alphaSource = 0
			-- 				obj.mat.opacityMap.monoOutput = 1
												
							--Temp report
							print "Regular Mask flag found"
						)
											
						--// Glossiness
						(type == 0x0C): \
						(
							obj.mat.glossinessMap = Bitmaptexture filename:texPath
							obj.mat.glossinessMap.alphasource = 2
						)									
											
						--// DecalMap  - dirtmap - Normal -----------
						(type == 0x0D): \
						(										
							if obj.mat.bumpmap == undefined then
							(
								obj.mat.bumpmap = Normal_bump()
							)
							obj.mat.bumpmap.bump_map						= Bitmaptexture filename:texPath
							obj.mat.bumpmap.bump_map.alphasource		= 2
												
							print "Decal Map type Texture flag found"
						)									
						--// DecalMask for above(?) - dirtmap - Normal ---------------
						(type == 0x0E): \
						(
			-- 				obj.mat.opacityMap = Bitmaptexture filename:texPath
			-- 				obj.mat.opacityMap.alphaSource = 0
			-- 				obj.mat.opacityMap.monoOutput = 1
												
							--Temp report
							print "Decal Mask Normal type Texture flag found"
						)	
											
						--// DecalMask -------------------------
						(type == 0x0F): \
						(
			-- 				obj.mat.opacityMap = Bitmaptexture filename:texPath
			-- 				obj.mat.opacityMap.alphaSource = 0
			-- 				obj.mat.opacityMap.monoOutput = 1
												
							--Temp report
							print "Decal Mask type Texture flag found"
						)
					)
				)
				else
				(
					format "Could not find texture: %\t for maptype %\n" texPath	type
				)
			)
		)
	)
)

--///// Overloaded version of the set_material function
--//// (this one takes the n file count, and thus skips the looping of each array over and over - must be run right after each loadModel function)
fn set_material \
						n	=
(	
	
	format "------------------we are inside set_material-------------------- \n" ---------
	
	--/////////////////// Prepare/Apply the Standard() material for each mesh ///////////////////
	for x=1 to rootData[2][n][9][1][1].count do
	(								
		_mesh = rootData[2][n][9][1][1][x]
				
		if (_mesh != undefined) then
		(				
			_mesh.mat = standard()
					
			------------------- Add composite to diffuse slot ----------------------
			_mesh.mat.diffusemap = CompositeTexturemap()					
			_mesh.mat.showInViewport = on --show map in viewport
		)
	)			
			
	for x2=1 to rootData[2][n][9][1][2].count do
	(
		for x3=1 to rootData[2][n][9][1][2][x2].count do 
		(
			_mesh			= rootData[2][n][9][1]	[2][x2][x3]
					
			if (_mesh != undefined) then
			(				
				_mesh.mat = standard()
						
				------------------- Add composite to diffuse slot ----------------------
				_mesh.mat.diffusemap = CompositeTexturemap()					
				_mesh.mat.showInViewport = on --show map in viewport
			)
		)
	)
	

	if (rootData[2][n][9][1] != undefined) AND \
		(rootData[2][n][9][1].count == 2) then
	(
				
		--Master Mesh (always 1, but we loop anyways, too keep the code generic) (notice index "1" before the .count)
		for x=1 to rootData[2][n][9][1][1].count do --[2] contains the sub sub, will be .count=0 if empty
		(
			obj			= rootData[2][n][9][1][1][x] 

			for t=1 to rootData[2][n][4][1][x][1].texPaths_arr[2].count do --both x and x2 will be "1" and only 1, but we loop anyways!
			(						
				type				= rootData[2][n][4][1][x][1].texPaths_arr[1][t] --get the type of texture (e.g. diff, specular, normal...etc)
				texPath		= rootData[2][n][4][1][x][1].texPaths_arr[2][t] --get the relative texpath

				--Run the texture function for the current looped mesh
				apply_textures \
										obj \
										type \
										texPath
				
				apply_decalTextures_runtime \
														n \
														obj
			)
			
			-- rootData[2][1][4][1].count
			-- 4
			-- rootData[2][n][4][1]   [x]   (one of the masters)
			-- #((texturePaths numTextures:6 _bones:#(0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...) attachPoints_arr:#() _padding2:2 _padding3:128 __u1:0 texPaths_arr:#(#(0, 1, 10, 12, 13, 14), #("variantmeshes/_variantmodels/man/skin/tex/roman_body_1_diffuse.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_1_normal.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_mask.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_1_gloss_map.dds", "variantmeshes/_variantmodels/man/skin/tex/default_decaldirtmap.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_decaldirtmask.dds")) texType:14 strLen_texPath_type6:256 strLen_texPath_type5:512 texPath:"variantmeshes/_variantmodels/man/skin/tex/roman_body_decaldirtmask.dds"))
			-- rootData[2][n][4][2]   [x].count (the subs of the master above)
			-- 3
			
			for x2=1 to rootData[2][n][9][1][2].count do
			(
				for x3=1 to rootData[2][n][9][1][2][x2].count do 
				(
					obj			= rootData[2][n][9][1][2][x2][x3]
					
					for t=1 to rootData[2][n][4][2] [x2][x3].texPaths_arr[2].count do --both x and x2 will be "1" and only 1, but we loop anyways!
					(
						type				= rootData[2][n][4][2][x2][x3].texPaths_arr[1][t] --get the type of texture (e.g. diff, specular, normal...etc)
						texPath		= rootData[2][n][4][2] [x2][x3].texPaths_arr[2][t] --get the relative texpath

						--Run the texture function for the current looped mesh
						apply_textures \
												obj \
												type \
												texPath
						
						apply_decalTextures_runtime \
																n \
																obj						
					)
				)
			)
		)
	)
				
	format "Done applying textures\n"	
)

--set_material function, but not runtime like the "set_material" function
fn set_material_v2 =
(	
	--/////////////////// Prepare/Apply the Standard() material for each mesh ///////////////////
	if rootData[2].count > 0 then
	(
		for n=1 to rootData[2].count do
		(
			for x=1 to rootData[2][n][9][1][1].count do
			(								
				_mesh = rootData[2][n][9][1][1][x]
				
				if (_mesh != undefined) then
				(				
					_mesh.mat = standard()
					
					------------------- Add composite to diffuse slot ----------------------
					_mesh.mat.diffusemap = CompositeTexturemap()					
					_mesh.mat.showInViewport = on --show map in viewport
				)
			)
			
			
			for x2=1 to rootData[2][n][9][1][2].count do
			(
				for x3=1 to rootData[2][n][9][1][2][x2].count do 
				(
					_mesh			= rootData[2][n][9][1]	[2][x2][x3]
					
					if (_mesh != undefined) then
					(				
						_mesh.mat = standard()
						
						------------------- Add composite to diffuse slot ----------------------
						_mesh.mat.diffusemap = CompositeTexturemap()					
						_mesh.mat.showInViewport = on --show map in viewport
					)
				)
			)
		)
	)	

	--/////////////////// Loop each Master for every file (the numMeshes in the header) then each submesh (if any) (the num in each submesh _prefix) ///////////////////	
	if rootData[2].count > 0 then
	(
		--// Master Meshes
		for n=1 to rootData[2].count do
		(
			if (rootData[2][n][9][1] != undefined) AND \
				(rootData[2][n][9][1].count == 2) then
			(
				
				--Master Mesh (always 1, but we loop anyways, too keep the code generic) (notice index "1" before the .count)
				for x=1 to rootData[2][n][9][1][1].count do --[2] contains the sub sub, will be .count=0 if empty
				(
					obj			= rootData[2][n][9][1]	[1][x] 

					for t=1 to rootData[2][n][4][1][x][1].texPaths_arr[2].count do --both x and x2 will be "1" and only 1, but we loop anyways!
					(						
						type			= rootData[2][n][4][1][x][1].texPaths_arr[1][t] --get the type of texture (e.g. diff, specular, normal...etc)
						texPath		= rootData[2][n][4][1][x][1].texPaths_arr[2][t] --get the relative texpath

						--Run the texture function for the current looped mesh
						apply_textures \
												obj \
												type \
												texPath
						
						apply_decalTextures_runtime \
																n \
																obj
					)
					
					-- rootData[2][1][4][1].count
					-- 4
					-- rootData[2][n][4][1]   [x]   (one of the masters)
					-- #((texturePaths numTextures:6 _bones:#(0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...) attachPoints_arr:#() _padding2:2 _padding3:128 __u1:0 texPaths_arr:#(#(0, 1, 10, 12, 13, 14), #("variantmeshes/_variantmodels/man/skin/tex/roman_body_1_diffuse.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_1_normal.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_mask.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_1_gloss_map.dds", "variantmeshes/_variantmodels/man/skin/tex/default_decaldirtmap.dds", "variantmeshes/_variantmodels/man/skin/tex/roman_body_decaldirtmask.dds")) texType:14 strLen_texPath_type6:256 strLen_texPath_type5:512 texPath:"variantmeshes/_variantmodels/man/skin/tex/roman_body_decaldirtmask.dds"))
					-- rootData[2][n][4][2]   [x].count (the subs of the master above)
					-- 3
						
					--// If there are subMeshes to the Master Meshes, loop them as well...	
					for x2=1 to rootData[2][n][9][1][2].count do
					(
						for x3=1 to rootData[2][n][9][1][2][x2].count do 
						(
							obj			= rootData[2][n][9][1]	[2][x2][x3]
							
							for t=1 to rootData[2][n][4][2] [x2][x3].texPaths_arr[2].count do --both x and x2 will be "1" and only 1, but we loop anyways!
							(								
								type			= rootData[2][n][4][2]  [x2][x3].texPaths_arr[1][t] --get the type of texture (e.g. diff, specular, normal...etc)
								texPath		= rootData[2][n][4][2]  [x2][x3].texPaths_arr[2][t] --get the relative texpath

								--Run the texture function for the current looped mesh
								apply_textures \
														obj \
														type \
														texPath								
								
								
								apply_decalTextures_runtime \
																			n \
																			obj
								
							)
						)
					)
					
				)
			)
		)		
		format "Done applying textures\n"
	)
)


fn sortObjects_to_layers =
(
	--MAP
--  	obj			= rootData[2][n][9][1][1][x] 
--  	obj			= rootData[2][n][9][1][2][x2][x3]
	

	n=1	
	lodNameBase = "Set_"	
	
	format "\n+++++-------++++++  rootData[2][n]: % +++++-------++++++  \n" rootData[2][n]
	
	 ---hack, because we could not load the variantmeshdefinition "animal_celtic_warhounds.variantmeshdefinition" (currently looking at the problem)
	for n=1 to 2 do
	(
		if rootData[2][n] != undefined then
	(
	--end of hack---------------------------------------------------------------------------------------------------------------------------------------------------
		
	-----------------------------	
	for x=1 to rootData[2][n][9][1][1].count do
	(
		FinalLodName		= lodNameBase + (x as string)
		newLayer			= LayerManager.newLayerFromName FinalLodName
		theLayer			= layerManager.getlayer x
			

			
		if iskindof rootData[2][n][9][1][1][x] node then
		(
			theLayer.addNode rootData[2][n][9][1][1][x]
		)
				
				
		for x2=1 to rootData[2][n][9][1][2].count do
		(				
			for x3=1 to rootData[2][n][9][1][2][x2].count do
			(				
				if iskindof rootData[2][n][9][1][2][x2][x3] node then
				(					
					theLayer.addNode rootData[2][n][9][1][2][x2][x3]					
				)
			)
		)
	)
	----------------------------------
	
	--hack, because we could not load the variantmeshdefinition "animal_celtic_warhounds.variantmeshdefinition" (currently looking at the problem)
	)		
	)
	--end of hack---------------------------------------------------------------------------------------------------------------------------------------------------

	
	
)
--//////////////////////////////////// End of New functions ////////////////////////////////////
clearlistener()-----------()----------()---------()---------()---------()----------()-----------()-----------()-----------()------------()-------------()-------------()-------------()


try
(
	DestroyDialog twr2Main
	closeRolloutFloater TWR2
)
catch
()

rollout twr2Main "Total War Rome 2 - Import" width:938 height:643
(
	listbox 'cbx_animList' "" pos:[180,199] width:735 height:16 align:#left
	combobox 'lbx_info' "Info" pos:[178,21] width:736 height:7 align:#left
	listbox 'lbx_xml' "Output" pos:[181,429] width:733 height:9 align:#left
	button 'btn_animList' "Load csv Anim List..." pos:[20,307] width:150 height:24 align:#left
	button 'btn_loadAnim' "Load Selected Animation" pos:[751,577] width:160 height:35 align:#left
	button 'btn_setRootPath' "Set Root Path..." pos:[583,10] width:124 height:24 align:#left tooltip:"the <\data> folder inside the Total War 2 installation directory"
	button 'btn_loadModel' "Load Model Directly..." pos:[20,41] width:150 height:24 align:#left
	button 'btn_loadAnimFromFile' "Load Anim From File..." pos:[590,577] width:160 height:35 align:#left
	checkbox 'chk_dontAnimateRoot' "Don't Animate Root" pos:[755,616] width:122 height:16 align:#left
	button 'btn_loadXMLdir' "Load XML dir..." pos:[20,282] width:150 height:24 align:#left
	button 'btn_loadXML_definition' "Load XML Definition..." pos:[20,66] width:150 height:24 align:#left
	button 'btn_loadXML_template' "Load XML Template..." pos:[20,257] width:150 height:24 align:#left
	button 'btn_restoreBindPose' "Restore Bind Pose" pos:[429,577] width:160 height:35 align:#left
	button 'btn_setAnimTables' "Set Anim Tables..." pos:[20,332] width:150 height:24 align:#left
	button 'btn_readAnimFragments' "Read Anim Fragments..." pos:[20,357] width:150 height:24 align:#left
	button 'btn_editConfig' "Edit Config File" pos:[708,10] width:100 height:24 align:#left
	button 'btn_deleteConfig' "Delete Config" pos:[809,10] width:100 height:24 align:#left
	button 'btn_debug' "Debug" pos:[24,576] width:150 height:35 align:#left
	edittext 'edt_filter' "" pos:[176,174] width:591 height:24 align:#left
	button 'btn_filter' "Filter" pos:[838,173] width:76 height:24 enabled:false align:#left
	checkbutton 'btn_regExp' "**" pos:[770,173] width:32 height:24 enabled:false checked:true align:#left
	checkbutton 'ckb_filterCase' "Aa" pos:[804,173] width:32 height:24 enabled:false align:#left
	button 'btn_deleteAllAnimKeys' "Delete All Anim Keys" pos:[268,577] width:160 height:35 align:#left
	checkbox 'chk_tga2dds' "Treat .tga textures as .dds" pos:[584,616] width:159 height:18 enabled:true checked:true align:#left
	button 'btn_getVarMeshRefs' "Get Variant Mesh Refs" pos:[20,382] width:150 height:24 align:#left	
	button 'btn_showAttachPoints' "Show Attach Points" pos:[21,450] width:150 height:24 align:#left
	button 'btn_showAttachPointsMatrix' "Show Attach Points Matrix" pos:[21,475] width:150 height:24 align:#left
	button 'btn_showAttachPointsName' "Show Attach Points Name" pos:[21,500] width:150 height:24 align:#left
	dropdownList 'ddl_animationSkelSpecific' "" pos:[179,151] width:589 height:21 align:#left
	checkbox 'chk_dontRotate' "Skip final rotation" pos:[456,617] width:108 height:14 checked:false align:#left
	
	on twr2Main open do
	(
		config_array = #() --reset array
		
		if (CONST_CONFIG_PATH != undefined) AND \
			(doesfileexist CONST_CONFIG_PATH) then
		(
			--//----------------------------- fill info box-----------------------------------------------			
			--will return an empty array if undefined
			config_array = create_config_array \
																	CONST_CONFIG_PATH \
																	config_array			
			lbx_info.items = config_array
			-----------------------------------------------------------------------------------------------	
			
			--fill animation list
			fpath = (getINISetting CONST_CONFIG_PATH "animations_files" "rome2_animations")
			if (fpath != undefined) AND \
				(pathconfig.islegalpath fpath) and \
				(doesfileexist fpath) then
			(
				setINISetting CONST_CONFIG_PATH "animations_files" "rome2_animations" (fpath as string)
				
				read_csv fpath
				cbx_animList.items = animList_arr
				
				setINISetting CONST_CONFIG_PATH "Animations" "count" (animList_arr.count as string)
				
				--//----------------------------- fill info box----------------------------------------------
				
				configPath = CONST_CONFIG_PATH
				config_array = create_config_array \
																	configPath \
																	config_array
				lbx_info.items = config_array
				-----------------------------------------------------------------------------------------------
				
				--enable buttons - since the animations file obviously has been found
				if config_array.count > 0 then
				(
					btn_filter.enabled = true
					btn_regExp.enabled = true
					ckb_filterCase.enabled = true
				)
			)		
			
			-----------------------------------------Populate Anim List ------------------------------------------
			animFragmentsDir = getinisetting CONST_CONFIG_PATH "animations" "animation_fragments"
		
			if (animFragmentsDir != undefined) and \
				(pathconfig.islegalpath animFragmentsDir) and \
				(doesfileexist animFragmentsDir) then
			(
				if (animFragmentsDir != undefined) and \
				(pathconfig.islegalpath animFragmentsDir) then
				(
					animFragmentList_arr = #(#(),#())
					
					pattern =  "*_fragment.txt"
					animFragmentList_arr[2] = (
															walkdir_xml \
																			animFragmentsDir \
																			pattern \
																			xmlVariantFiles_arr
														)
					
					for i=1 to animFragmentList_arr[2].count do
					(
						Append animFragmentList_arr[1] ( getFilenameFile  animFragmentList_arr[2][i] )
					)
					
					ddl_animationSkelSpecific.items = animFragmentList_arr[1]
				)
			)			
			------------------------------------------ End of Populate Anim List -------------------------------------		
		)
	)
	on cbx_animList selected arg do
	(
		--format "%\n" cbx_animList.items[arg]
	)
	on cbx_animList doubleClicked arg do
	(
		rmv2anim = pathConfig.appendPath (trimright (trimleft rootPath)) \
														(trimright (trimleft cbx_animList.items[arg]))
		
		if (rmv2anim != undefined) AND \
			(doesfileexist rmv2anim) then
		(			
			if chk_dontAnimateRoot.state then
			(
				animateRoot = false
			)
			else
			(
				animateRoot = true
			)
			
			loadAnimFromFile \
									g_rmv2 \
									rmv2anim
		)
	)
	on btn_animList pressed do
	(
		fpath = getOpenFileName \
											caption:"Open Animations List" \
											filename:(getINISetting CONST_CONFIG_PATH "animations_files" "rome2_animations") \
											types:"Excel(*.csv)|*.csv|All|*.*|"
		
		if (fpath != undefined) AND \
			(pathconfig.islegalpath fpath) and \
			(doesfileexist fpath) then
		(
			setINISetting CONST_CONFIG_PATH "animations_files" "rome2_animations" (fpath as string)	
			
			read_csv fpath
			cbx_animList.items = animList_arr
			
			setINISetting CONST_CONFIG_PATH "Animations" "count" (animList_arr.count as string)
			
			--//----------------------------- fill info box----------------------------------------------
			configPath = CONST_CONFIG_PATH
			config_array = create_config_array \
																configPath \
																config_array
			lbx_info.items = config_array
			-----------------------------------------------------------------------------------------------
		)
	)
	on btn_loadAnim pressed do
	(
		if (cbx_animList.selected != undefined) AND \
			(iskindof cbx_animList.selected string) then
		(
			rootPath = (getINISetting CONST_CONFIG_PATH "root" "rootPath")
			
			rmv2anim = pathConfig.appendPath (trimright (trimleft rootPath)) \
															(trimright (trimleft cbx_animList.selected))
		
			if (rmv2anim != undefined) AND \
				(doesfileexist rmv2anim) then
			(
				--///// For info only /////
				str_rigging_data.animation_name = filenameFromPath  rmv2anim
				str_rigging_data.g_rmv2 = g_rmv2
				
				
				if chk_dontAnimateRoot.state then
				(
					animateRoot = false
				)
				else
				(
					animateRoot = true
				)			
	
				loadAnimFromFile \
										g_rmv2 \
										rmv2anim
				
				
				if NOT chk_dontRotate.state do
				(
					rotate_models()
				)
	
			)
		)
	)
	on btn_setRootPath pressed do
	(	
		--If the file config.ini file does not exist, then create it...
		if (doesfileexist CONST_CONFIG_PATH) == false then
		(
			setINISetting CONST_CONFIG_PATH "" "" "" --the setINISetting method creates a file if there is none
		)
		
		--If the file config.ini does exist
		if (doesfileexist CONST_CONFIG_PATH) then
		(
			confirm = yesNoCancelBox "WARNING, this will reset the config.ini and set new paths, continue?" \
												title:"WARNING" \
												beep:true
				
			if confirm == #yes then
			(
				--initDir = @"\\diskstation4\Game_Models\Games\TotalWar_Rome_2\extract\Total War Rome II\data"
				initDir = getINISetting CONST_CONFIG_PATH "Directories" "rootpath"
					
				if initDir != undefined and pathconfig.islegalpath initDir then
				(			
					rootPath = getSavePath caption:"Set Root Path" initialDir:initDir
				)
				else
				(
					rootPath = getSavePath caption:"Set Root Path" initialDir:sysInfo.currentdir 
				)
					
				if (rootPath != undefined) AND \
					(pathConfig.isLegalPath rootPath) then
				(	
										
					try (deleteFile CONST_CONFIG_PATH) catch()
					
					--/////// SET ROOT PATH ////////
					setINISetting CONST_CONFIG_PATH "root" "rootpath" rootPath					
					
					--//////////////////// SET ALL OTHER PATH RELATIVE TO THE ROOTPATH ////////////////////
					--data
					setINISetting CONST_CONFIG_PATH "root" "animations" (pathconfig.appendpath rootPath "\\animations")
					setINISetting CONST_CONFIG_PATH "root" "animations_cinematic" (pathconfig.appendpath rootPath "\\animations_cinematic")
						
						--data\animations
						setINISetting CONST_CONFIG_PATH "animations" "skeletons" (pathconfig.appendpath rootPath "\\animations\\skeletons")
						setINISetting CONST_CONFIG_PATH "animations" "rome2" (pathconfig.appendpath rootPath "\\animations\\rome2")				
						setINISetting CONST_CONFIG_PATH "animations" "animation_fragments" (pathconfig.appendpath rootPath "\\animations\\animation_fragments")
						setINISetting CONST_CONFIG_PATH "animations" "animation_tables" (pathconfig.appendpath rootPath "\\animations\\animation_tables")			
						setINISetting CONST_CONFIG_PATH "animations" "campaign_animation_tables" (pathconfig.appendpath rootPath "\\animations\\campaign_animation_tables")
						setINISetting CONST_CONFIG_PATH "animations" "matched_combat" (pathconfig.appendpath rootPath "\\animations\\matched_combat")
			
						--data\animations_cinematic
						setINISetting CONST_CONFIG_PATH "animations_cinematic" "rome2" (pathconfig.appendpath rootPath "\\animations_cinematic\\rome2")
			
						--data\rigidmodels
						setINISetting CONST_CONFIG_PATH "root" "rigidmodels" (pathconfig.appendpath rootPath "\\rigidmodels")		
						
						--data\variantmeshes
						setINISetting CONST_CONFIG_PATH "root" "variantmeshes" (pathconfig.appendpath rootPath "\\variantmeshes")
						
							--data\variantmeshes\variantmeshtemplates
							setINISetting CONST_CONFIG_PATH "variantmeshes" "variantmeshtemplates" (pathconfig.appendpath rootPath "\\variantmeshes\\variantmeshtemplates")
							
							--data\variantmeshes\variantmeshdefinitions
							setINISetting CONST_CONFIG_PATH "variantmeshes" "variantmeshdefinitions" (pathconfig.appendpath rootPath "\\variantmeshes\\variantmeshdefinitions")
							
							--data\variantmeshes\_variantmodels
							setINISetting CONST_CONFIG_PATH "variantmeshes" "_variantmodels" (pathconfig.appendpath rootPath "\\variantmeshes\\_variantmodels")
				)
				
				--//----------------------------- fill info box----------------------------------------------
				--will return an empty array if undefined
				config_array = create_config_array \
																	CONST_CONFIG_PATH \
																	config_array
				lbx_info.items = config_array
				----------------------------------------------------------------------------------------------
			)
		)
		else
		(
			format "No such file to delete!\n"
		)
	)
	on btn_loadModel pressed do
	(
		g_rmv2 = getOpenFileName types:"Variant Mesh Rigid Model v2|*.rigid_model_v2|"
		
		if (g_rmv2 != undefined) AND \
			(doesfileexist g_rmv2) then
		(			
			--------------reset arrays--------------
			--// This is dirty coding and needs to be changed later
			skeleton_type_arr = #()
				
			mesh2_rig_animate_arr = #(#(),#())
				
			--For now, if we do not empty the array, we cannot procede with an array that contains any item
			bones_array = #()
	
			--array used for filling and storing the listing the animations (the large box)
			animList_arr = #()
				
			str_header = header()				
			data_array = #( \		
									#(), 				\	-- _prefix subinfo headers description
									#(#(),#()), 	\	-- [2] submesh chunk description
									#(#(),#()), 	\	-- [3] parsed mesh chunk
									#(#(),#()), 	\	-- [4] texture paths
									#(#(),#()), 	\	-- [5] attach_points
									#(),			 	\	-- [6] header ( only 1 for each file)
									#(),			 	\	-- [7] built mesh node in [1] and its attach points
									#(#(),#()),	\	-- [8] have attachpoints
									#()	 			\ 	-- [9][1] Mesh Nodes	[9][n][1] = masterMesh Node		[9][n][2] = The submesh Nodes belonging to the masterMesh
								)
							
			meshes_to_texture = #(#(),#())
						
			inv_matrix_arr = #()
			matrix_arr = #()
			------------------------------------------
			
			if chk_tga2dds.checked then
			(
				chk_tga2dds == true
			)
			else
			(
				chk_tga2dds == false
			)
	
			--/*	
			------test-------	because loading a model directly missed applying textures, but this seems to work	
				
				
				str_header = header()
				data_array = #( \		
										#(), 				\	-- _prefix subinfo headers description
										#(#(),#()), 	\	-- [2] submesh chunk description
										#(#(),#()), 	\	-- [3] parsed mesh chunk
										#(#(),#()), 	\	-- [4] texture paths
										#(#(),#()), 	\	-- [5] attach_points
										#(),			 		\	-- [6] header ( only 1 for each file)
										#(),			 		\	-- [7] built mesh node in [1] and its attach points
										#(#(),#()),	\	-- [8] have attachpoints
										#()	  				\ 	-- [9][1] Mesh Nodes	[9][n][1] = masterMesh Node		[9][n][2] = The submesh Nodes belonging to the masterMesh
									)
				
				loadModel \
									x \						--same as the number of data_arrays in rootData[2].count		
									data_array \			--current data_array, later to be added to rootData, then reset, etc... until done
									g_rmv2			--the full path to the rigid mesh file
				
				
				
				---------------------- Store the Data ----------------------
				--Add the header for this file						
				Append data_array[6] str_header
				
				--Add the finished data_array to the respective g_rmv2 (sorted mesh file path)
				Append rootData[2] data_array				
				------------------ End of Store the Data ------------------
	
					
				
				set_attachPoints \
										meshFilePath				
				
				
				------------------------------------------------ The Decal Textures ----------------------------------------------------
				--Apply the materials and textures
				decals_targets_arr = check_if_meshFile_has_decals \
																						g_rmv2
				--print decals_targets_arr
				set_material (rootData[2].count) --we could also use x as the counter, exactly the same thing as rootData[2].count
				-------------------------------------------- End of The Decal Textures ------------------------------------------------				
				
	-- 				have_Skeleton_check_rootData()
													
				
				gc()
			
			-----end of test------
			--*/
			
			/*
			loadModel \
							1 \
							data_array \
							g_rmv2
			*/
			
			if NOT chk_dontRotate.state do
			(
				rotate_models()
			)		
		)
	)
	on btn_loadAnimFromFile pressed do
	(
		rmv2anim = getOpenFileName types:"All|*.*|"
		
		if (rmv2anim != undefined) AND \
			(doesfileexist rmv2anim) then
		(
			
			if chk_dontAnimateRoot.state then
			(
				animateRoot = false
			)
			else
			(
				animateRoot = true
			)
			
			skeletonMatch = confirm_correct_skeleton \
																		g_rmv2 \
																		rmv2anim
			if skeletonMatch then
			(
				lbx_xml.items = #("Loading Animation...")
				
				loadAnimFromFile \
										g_rmv2 \
										rmv2anim				
				
				lbx_xml.items = #("Done Loading Animation!")			
			)
			else
			(
				lbx_xml.items = #("Animation Skeleton is not compatible with the current Skeleton")
			)	
		)
	)
	on btn_loadXMLdir pressed do
	(
		variantMeshDefDir = getINISetting CONST_CONFIG_PATH "root" "variantmeshes"
		
		if (variantMeshDefDir != undefined) AND \
			(pathConfig.isLegalPath variantMeshDefDir) then
		(
			dir = getSavePath caption:"Chose folder" initialDir:variantMeshDefDir
		)
		else
		(
			dir = getSavePath caption:"Chose folder"
		)
		
		if (dir != undefined) and \
			(pathconfig.islegalpath dir) then
		(
			pattern =  "*.variantmeshdefinition"
			lbx_xml.items = (
									walkdir_xml \
														dir \
														pattern \
														xmlVariantFiles_arr
								  )
		)
	)
	on btn_loadXML_definition pressed do
	(
		variantmesh_xml_file =  getOpenFileName types:"Variantmesh Definition(*.variantmeshdefinition)"
		
		if (variantmesh_xml_file != undefined) AND \
			(pathconfig.islegalpath variantmesh_xml_file) AND \
			(doesfileexist variantmesh_xml_file) then
		(
			setINISetting CONST_CONFIG_PATH "recent_variantmesh" "xml_definition" variantmesh_xml_file
			
			
			
			--/*--!!??
			-----------------------------------------
			------------------ reset arrays -----------
			SEPARATED_DEFS_ARR = #()			
			rootData = #(
								#(), --path to mesh file
								#(), --the data_array for this file
								#()
								)
			----------------------------------------------------			
			get_varMeshRefs \
									variantmesh_xml_file  ---it seems the problem is here... 2016-05-02 --update, the problem is now fixed...
			
			---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
			format "\n =============================   we are here ============================= \n\n"
			format "variantmesh_xml_file: %\n" variantmesh_xml_file
			---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
	
			---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
			format "\n =============================  we are here ============================= \n"
			format "rootData: %\n" rootData
			---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------	---------------
			
			rootData = get_the_RANDOM_meshes()
			---------------------------------------------
			-----------------------------------------
			--*/--!!??			
			
	
			--------------reset arrays--------------
			--// This is dirty coding and needs to be changed later
			skeleton_type_arr = #()
			
			mesh2_rig_animate_arr = #(#(),#())
			
			--For now, if we do not empty the array, we cannot procede with an array that contains any item
			bones_array = #()
	
			--array used for filling and storing the listing the animations (the large box)
			animList_arr = #()
				
			str_header = header()			
			data_array = #( \		
									#(), 				\	-- _prefix subinfo headers description
									#(#(),#()), 	\	-- [2] submesh chunk description
									#(#(),#()), 	\	-- [3] parsed mesh chunk
									#(#(),#()), 	\	-- [4] texture paths
									#(#(),#()), 	\	-- [5] attach_points
									#(),			 	\	-- [6] header ( only 1 for each file)
									#(),			 	\	-- [7] built mesh node in [1] and its attach points
									#(#(),#()),	\	-- [8] have attachpoints
									#() 				\ 	-- [9][1] Mesh Nodes	[9][n][1] = masterMesh Node		[9][n][2] = The submesh Nodes belonging to the masterMesh
								)
			
			meshes_to_texture = #(#(),#())
					
			inv_matrix_arr = #()
			matrix_arr = #()			
			------------------------------------------
			
			--/*
			for x=1 to rootData[1].count do
			--for x=1 to SEPARATED_DEFS_ARR[x] then
			(								
				if chk_tga2dds.checked then
				(
					chk_tga2dds == true
				)
				else
				(
					chk_tga2dds == false
				)
				
				meshFilePath = rootData[1][x]
				
				str_header = header()
				data_array = #( \		
										#(), 				\	-- _prefix subinfo headers description
										#(#(),#()), 	\	-- [2] submesh chunk description
										#(#(),#()), 	\	-- [3] parsed mesh chunk
										#(#(),#()), 	\	-- [4] texture paths
										#(#(),#()), 	\	-- [5] attach_points
										#(),			 		\	-- [6] header ( only 1 for each file)
										#(),			 		\	-- [7] built mesh node in [1] and its attach points
										#(#(),#()),	\	-- [8] have attachpoints
										#()	  				\ 	-- [9][1] Mesh Nodes	[9][n][1] = masterMesh Node		[9][n][2] = The submesh Nodes belonging to the masterMesh
									)
				
				loadModel \
									x \						--same as the number of data_arrays in rootData[2].count		
									data_array \			--current data_array, later to be added to rootData, then reset, etc... until done
									meshFilePath			--the full path to the rigid mesh file
				
				
				
				---------------------- Store the Data ----------------------
				--Add the header for this file						
				Append data_array[6] str_header
				
				--Add the finished data_array to the respective g_rmv2 (sorted mesh file path)
				Append rootData[2] data_array				
				------------------ End of Store the Data ------------------
	
					
				
				set_attachPoints \
										meshFilePath				
				
				
				------------------------------------------------ The Decal Textures ----------------------------------------------------
				--Apply the materials and textures
				decals_targets_arr = check_if_meshFile_has_decals \
																						meshFilePath
				--print decals_targets_arr
				set_material (rootData[2].count) --we could also use x as the counter, exactly the same thing as rootData[2].count
				-------------------------------------------- End of The Decal Textures ------------------------------------------------				
				
	-- 				have_Skeleton_check_rootData()
													
				
				gc()
			)
			
			if NOT chk_dontRotate.state do
			(
				rotate_models()
			)			
			
			--format "rootData[2][1] : %" rootData[2][1]
			
			--/* temp off		
			--/////////////// Set Material ///////////////			
			--set_material()
	 		sortObjects_to_layers()
			--/////////////////////////////////////////////
			--*/
		)
	)
	on btn_loadXML_template pressed do
	(
		xml_template =  getOpenFileName types:"All|*.*|"
		
		if (xml_template != undefined) AND \
			(pathconfig.islegalpath xml_template) AND \
			(doesfileexist xml_template) then
		(
			setINISetting CONST_CONFIG_PATH "recent_variantmeshTemplate" "xml_template" xml_template
			
			fill_xml_arrays \
								str_read_xml \
								xml_template \
								"template"
		)
	)
	on btn_restoreBindPose pressed do
	(
		restore_bindPose()		
	
		if safe2rotate then
		(
			if NOT chk_dontRotate.state do
			(
				rotate_models()
			)			
		)
	)
	on btn_setAnimTables pressed do
	(
		animation_tables_file = getOpenFileName \
										caption:"Chose animation_tables file" \
										types:"Text(*.txt)|*.txt|All|*.*|" \
										filename:(getINISetting CONST_CONFIG_PATH "animations" "animation_tables")
		
		if (animation_tables_file != undefined) and \
			(pathconfig.islegalpath animation_tables_file) and \
			(doesfileexist animation_tables_file) then
		(
			setINISetting CONST_CONFIG_PATH "files" "animation_tables" animation_tables_file
			
			read_AnimationTables \
											animation_tables_file
		)
		
		--REPORT
		for i=1 to animation_tables_arr.count do
		(
			print animation_tables_arr[i]
		)
	)
	on btn_readAnimFragments pressed do
	(
		animFragmentsFile = getOpenFileName types:"Text(*.txt)|*.txt|All|*.*|"
		
		if (animFragmentsFile != undefined) and \
			(pathconfig.islegalpath animFragmentsFile) and \
			(doesfileexist animFragmentsFile) then
		(
			read_AnimationFragments \
												animFragmentsFile
		)
		
		--REPORT to console
	-- 		for i=1 to animation_fragments_arr.count do
	-- 		(
	-- 			print animation_fragments_arr[i]
	-- 		)
		
		---------------------------------
	-- 		struct animation_fragments
	-- 		(
	-- 			version = "",
	-- 			
	-- 			skeleton_type = "", --filename(without extension) of the .bone_inv_trans_mats & .anim in (this is used for the rig and bindpose) ..data\animations\skeletons
	-- 			cinematic = false,
	-- 			
	-- 			anim_type = "",
	-- 			filename = "",
	-- 			metadata = "",
	-- 			blend_in_time = "",
	-- 			weapon_bone_1 = "",
	-- 			weapon_bone_2 = "",
	-- 			weapon_bone_3 = "",
	-- 			weapon_bone_4 = ""
	-- 		)
		---------------------------------
		
		temp_arr = #()
	
		for i=1 to animation_fragments_arr.count do
		(
			version							= animation_fragments_arr[i].version as string
			
			anim_type						= animation_fragments_arr[i].anim_type as string
			cinematic						= animation_fragments_arr[i].cinematic as string
			
			skeleton_type					= animation_fragments_arr[i].skeleton_type  as string
			filename							= animation_fragments_arr[i].filename  as string
			metadata						= animation_fragments_arr[i].metadata  as string
			blend_in_time					= animation_fragments_arr[i].blend_in_time  as string
			
			weapon_bone_1				= animation_fragments_arr[i].weapon_bone_1 as string
			weapon_bone_2				= animation_fragments_arr[i].weapon_bone_2  as string
			weapon_bone_3				= animation_fragments_arr[i].weapon_bone_3  as string
			weapon_bone_4				= animation_fragments_arr[i].weapon_bone_4  as string
			
			Append temp_arr (version)
			Append temp_arr (anim_type + ", " + skeleton_type  + ", " + cinematic + ", " + filename + ", " + metadata + ", " + blend_in_time)
			Append temp_arr (weapon_bone_1 + ", " + weapon_bone_2  + ", " + weapon_bone_3 + ", " + weapon_bone_4 )
		)
		
		lbx_xml.items = temp_arr
		--end of REPORT
	)
	on btn_editConfig pressed do
	(
		if (doesfileexist CONST_CONFIG_PATH) then
		(
			shellLaunch "explorer.exe" CONST_CONFIG_PATH
		)
	)
	on btn_deleteConfig pressed do
	(
		if (doesfileexist CONST_CONFIG_PATH) then
		(
			 confirm = yesNoCancelBox "WARNING, this will delete the config.ini file (you have to reconfigure paths after deletion), continue with deletion?" \
													title:"WARNING" \
													beep:true
			
			if confirm == #yes then
			(
				try (deleteFile CONST_CONFIG_PATH) catch()
				
				--//----------------------------- fill info box----------------------------------------------					
				--will return an empty array if undefined
				config_array = create_config_array \
																	CONST_CONFIG_PATH \
																	config_array			
				lbx_info.items = config_array
				-----------------------------------------------------------------------------------------------
			)
		)
		else
		(
			format "No such file to delete!\n"
		)
	)
	on btn_debug pressed do
	(
		print str_header.skeleton_type
	)
	on edt_filter changed arg do
	(
		if edt_filter.text != "" then
		(
			btn_filter.enabled = true
			btn_regExp.enabled = true
			ckb_filterCase.enabled = true
		)
		else
		(
			wasLoaded = getinisetting CONST_CONFIG_PATH "animations_files" "rome2_animations"
			
			if wasLoaded == "" then
			(
				btn_filter.enabled = false
				btn_regExp.enabled = false
				ckb_filterCase.enabled = false
			)
		)
	)
	on btn_filter pressed do
	(
		fPath = getinisetting CONST_CONFIG_PATH "animations_files" "rome2_animations"
		
		if (fpath != undefined) AND \
			(pathconfig.islegalpath fpath) and \
			(doesfileexist fpath) then
		(
			animList_arr = #()
			read_csv fPath			
			
			filtered_array = #()
			for x=1 to animList_arr.count do
			(
				if ckb_filterCase.checked == true then --case sensitive
				(
					if btn_regExp.checked == true then
					(
						if (matchpattern animList_arr[x] pattern:("*"+ edt_filter.text +"*") ignoreCase:false) == true then
						(
							Append filtered_array animList_arr[x]
						)
					)
					else
					(
						if (matchpattern animList_arr[x] pattern:(edt_filter.text) ignoreCase:false) == true  then
						(
							Append filtered_array animList_arr[x]
						)
					)
				)
				else --case insensitive
				(
					if btn_regExp.checked == true then
					(
						if matchpattern animList_arr[x] pattern:("*"+ edt_filter.text +"*") == true then
						(
							Append filtered_array animList_arr[x]
						)
					)
					else
					(
						if matchpattern animList_arr[x] pattern:(edt_filter.text) == true then
						(
							Append filtered_array animList_arr[x]
						)
					)
				)
			)
			--fill the box with the filtered array
			cbx_animList.items = filtered_array
		)
	)
	on btn_deleteAllAnimKeys pressed do
	(
		 confirm = yesNoCancelBox "WARNING, this will delete all the animation keys, continue with deletion?" \
													title:"WARNING" \
													beep:true
	
		if confirm == #yes then
		(
			try
			(
				sliderTime = 0f
				deleteKeys objects #allKeys
			) 
			catch()
		)
	)
	on btn_getVarMeshRefs pressed do
	(
		format "skeleton_type_arr: %\n" skeleton_type_arr
	
		varMeshDef_file =  getOpenFileName types:"variantmeshdefinition |*.variantmeshdefinition|"
		
		if (varMeshDef_file != undefined) and \
			(pathconfig.islegalpath varMeshDef_file) and \
			(doesfileexist varMeshDef_file) then
		(
			------------------ reset arrays ------------------ 
			SEPARATED_DEFS_ARR = #()			
			rootData = #(
								#(), --path to mesh file
								#(), --the data_array for this file
								#()
								)
			----------------------------------------------------
			
			get_varMeshRefs \
									varMeshDef_file
			
			rootData = get_the_RANDOM_meshes()
		)
		
		--the final sorted meshes from the variantdefinition file
		print rootData[1]
	)
	on btn_showAttachPoints pressed do
	(
		info_arr = #()
		
		for x=1 to rootData[2].count do
		(
			for i=1 to rootData[2][x].count do
			(
				Append info_arr (rootData[2][x][5][i].NsubMesh as string)
				Append info_arr (rootData[2][x][5][i] as string)
			)
		)
		
		lbx_xml.items = info_arr 
	)
	on btn_showAttachPointsMatrix pressed do
	(
		info_arr = #()
		
		for x=1 to rootData[2].count do
		(
			for i=1 to rootData[2][x].count do
			(
				Append info_arr (rootData[2][x][5][i].NsubMesh as string)
				Append info_arr (rootData[2][x][5][i].matrix as string)
			)
		)
		
		lbx_xml.items = info_arr 
	)
	on btn_showAttachPointsName pressed do
	(
		info_arr = #()
		
		for x=1 to rootData[2].count do
		(
			for i=1 to rootData[2][x].count do
			(
				Append info_arr (rootData[2][x][5][i].NsubMesh as string)
				Append info_arr (rootData[2][x][5][i]._name as string)
			)
		)
		
		lbx_xml.items = info_arr 
	)
	on ddl_animationSkelSpecific selected arg do
	(
		animFragmentsFile = animFragmentList_arr[2][arg]		
		
		if (animFragmentsFile != undefined) AND \
			(doesfileexist animFragmentsFile) then
		(
			read_AnimationFragments \
												animFragmentsFile
			
			temp_arr = #()
		
			for i=1 to animation_fragments_arr.count do
			(
				version = animation_fragments_arr[i].version as string
				
				anim_type = animation_fragments_arr[i].anim_type as string
				cinematic = animation_fragments_arr[i].cinematic as string
				
				skeleton_type = animation_fragments_arr[i].skeleton_type  as string
				filename = animation_fragments_arr[i].filename  as string
				metadata = animation_fragments_arr[i].metadata  as string
				blend_in_time = animation_fragments_arr[i].blend_in_time  as string
				
				weapon_bone_1 = animation_fragments_arr[i].weapon_bone_1 as string
				weapon_bone_2 = animation_fragments_arr[i].weapon_bone_2  as string
				weapon_bone_3 = animation_fragments_arr[i].weapon_bone_3  as string
				weapon_bone_4 = animation_fragments_arr[i].weapon_bone_4  as string
				
				Append temp_arr version
				Append temp_arr skeleton_type
				Append temp_arr anim_type
				Append temp_arr filename				
				--Append temp_arr (weapon_bone_1 + ", " + weapon_bone_2  + ", " + weapon_bone_3 + ", " + weapon_bone_4 )
			)
		
			cbx_animList.items = temp_arr			
		)
	)
)


rollout twr2_meshInfo "Mesh Info" width:938 height:50
(

)
-----------------------------------------------
-----------------------------------------------
--createdialog twr2Main
TWR2 = newRolloutFloater "TWR 2" 938 670
addRollout twr2Main TWR2
--addRollout twr2_skeletonInfo TWR2 rolledUp:true
-----------------------------------------------
-----------------------------------------------


--////////////////////////////////////////// Callbacks //////////////////////////////////////////
fn print_animNotification =
(
	print "Animation Changed"
	
	rollout twr2_skeletonInfo "Skeleton Info" width:938 height:168
	(
		listbox lbx_riggingInfo "Rigging Data" pos:[17,12] width:903 height:8
		
		on twr2_skeletonInfo open do
		(
			local arr = #()
			for i=1 to skeleton_type_arr.count do
			(
				Append str_rigging_data.skeleton_name skeleton_type_arr[i]
			)
			
			--////////// create the info array //////////
			Append arr "Model:"
			Append arr str_rigging_data.g_rmv2
			
			Append arr "Skeleton Name:"
			Append arr (str_rigging_data.skeleton_name as string)
			
			Append arr "Animation Name:"
			Append arr str_rigging_data.animation_name
			--/////// End of create the info array ///////
			
			lbx_riggingInfo.items = arr
		)
	)
	
	addRollout twr2_skeletonInfo TWR2 rolledUp:true
)
callbacks.addScript #animationRangeChange "print_animNotification()"
--////////////////////////////////////// End of Callbacks ///////////////////////////////////