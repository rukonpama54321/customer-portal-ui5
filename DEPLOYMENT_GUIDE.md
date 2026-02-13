# Deployment to SAP ERP Fiori Launchpad

## Method 1: Using SAP Web IDE / Business Application Studio (Recommended)

### Steps:
1. **Zip the dist folder**
   - Navigate to `E:\Customer Portal\dist`
   - Create a ZIP file of all contents (not the dist folder itself)

2. **Upload via /UI2/FLPD_CUST Transaction**
   - Login to SAP ERP (https://eccdev.nrl.com:8001)
   - Go to transaction `/UI2/FLPD_CUST`
   - Click on "Transport" → "Import"
   - Upload the ZIP file
   - Provide:
     - Package: `ZCUST_PORTAL` (or create new)
     - Transport Request: (your transport)
     - BSP Application Name: `ZCUSTINDENT`

## Method 2: Using ABAP Repository Upload

### Steps:
1. **Go to SE80 Transaction**
   - Login to SAP ERP
   - Transaction: `SE80`
   - Repository Browser → BSP Application

2. **Create BSP Application**
   - Right-click → Create → BSP Application
   - Application Name: `ZCUSTINDENT`
   - Description: `Customer Indent Portal`
   - Package: `ZCUST_PORTAL`

3. **Upload Files**
   - Right-click on the BSP app → Import → Web Objects
   - Select all files from `dist` folder
   - Upload and activate

## Method 3: Using nwabap-ui5uploader (Automated)

Run the deploy script after configuration.

## Create Fiori Launchpad Tile

After deployment, create a tile in Launchpad Designer:

1. **Go to /UI2/FLPD_CUST**
2. **Create Catalog**
   - Catalog ID: `ZCP_CATALOG`
   - Title: `Customer Portal Apps`

3. **Create Tile**
   - Type: `App Launcher - Static`
   - Semantic Object: `CustomerIndent`
   - Action: `display`
   - Title: `Customer Indent`
   - Subtitle: `Create and Manage Customer Indents`
   
4. **Configure Navigation Target**
   - Application Type: `SAPUI5 Component`
   - SAPUI5 Component: `customerindent`
   - BSP Application: `ZCUSTINDENT`

5. **Assign to Group**
   - Create or select group
   - Add tile to group

6. **Assign to Role**
   - Assign catalog to user role
   - Transport changes

## Test in Fiori Launchpad

1. Clear browser cache
2. Login to SAP
3. Go to `/UI2/FLP`
4. Your tile should appear
5. Click to launch the app

## Important Notes

- **Package Name**: `ZCUST_PORTAL` (adjust if needed)
- **BSP App Name**: `ZCUSTINDENT` (must start with Z/Y)
- **Component Name**: `customerindent` (from manifest.json)
- **Transport**: Always use a transport request for deployment
