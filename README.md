# Customer Portal - SAP UI5 Application

A comprehensive SAP UI5 application for managing customer indent operations — supporting both bulk indent creation and direct indent via SAP WebDynpro.

## 🚀 Features

- **🏠 Home Screen** - Central landing page with navigation to Bulk Indent and Direct Indent
- **📦 Bulk Indent** - Create and manage bulk indents from sales orders with agent allocation
- **🔗 Direct Indent** - Seamlessly navigate to SAP WebDynpro application for direct indent entry
- **🔍 Sales Order Lookup** - Advanced search and filtering for sales orders
- **👥 Agent Allocation** - Assign agents to orders with quantity management
- **🚛 Transporter Management** - Handle carrier selection and GSTN details
- **✅ Data Validation** - Comprehensive validation and error handling
- **📱 Responsive Design** - Works seamlessly on desktop and mobile devices
- **🔐 Role-based Access** - View-only mode for different user roles

## 📋 Table of Contents

- [Features](#-features)
- [Technology Stack](#-technology-stack)
- [Project Structure](#-project-structure)
- [Installation](#-installation--setup)
- [Usage](#-usage)
- [Key Components](#-key-components)
- [API Integration](#-api-integration)
- [Contributing](#-contributing)
- [License](#-license)

## 🛠 Technology Stack

- **Frontend**: SAP UI5 (JavaScript Framework)
- **Backend**: SAP OData V2 Services
- **Language**: JavaScript, XML
- **UI Library**: SAP Fiori design principles
- **Data Binding**: Two-way data binding with JSON models

## 📁 Project Structure

```
Customer Portal/
├── webapp/
│   ├── controller/              # MVC Controllers
│   │   ├── Home.controller.js             # Home screen navigation
│   │   ├── CustomerBulkIndent.controller.js  # Bulk indent search & listing
│   │   └── ManageBulkIndent.controller.js    # Bulk indent creation & management
│   ├── view/                    # XML Views
│   │   ├── App.view.xml                   # App shell
│   │   ├── Home.view.xml                  # Home screen
│   │   ├── CustomerBulkIndent.view.xml    # Bulk indent search interface
│   │   └── ManageBulkIndent.view.xml      # Bulk indent management UI
│   ├── css/                     # Custom stylesheets
│   │   └── style.css
│   ├── util/                    # Utility functions
│   │   ├── formatter-dbg.js               # Data formatters
│   │   └── UserInfo-dbg.js               # User utilities
│   ├── model/                   # Data models
│   │   └── models.js
│   ├── i18n/                    # Internationalization
│   │   ├── i18n.properties
│   │   └── i18n_en.properties
│   ├── img/                     # Images and assets
│   ├── test/                    # Test files
│   ├── manifest.json            # App configuration
│   └── index.html              # Entry point
├── ui5.yaml                     # UI5 tooling configuration
├── package.json                 # Node.js dependencies
└── README.md                   # Project documentation
```

## 🚀 Installation & Setup

### Prerequisites
- Node.js (v14 or higher)
- SAP UI5 CLI
- Git

### Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/customer-portal-ui5.git
   cd customer-portal-ui5
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Install UI5 CLI globally (if not already installed):**
   ```bash
   npm install -g @ui5/cli
   ```

4. **Start the development server:**
   ```bash
   npm start
   # or
   ui5 serve
   ```

5. **Open in browser:**
   Navigate to `http://localhost:8080` to view the application

## 💡 Usage

### 1. Home Screen
- Landing page presented after login
- Two options available:
  - **Bulk Indent** — navigate to the bulk indent management flow
  - **Direct Indent** — opens the SAP WebDynpro application (`ZSD_CUST_INDENT_DIR_INBAPP`) in a new tab using the existing SAP session

### 2. Bulk Indent — Sales Order Search
- Use the search functionality to find sales orders by various criteria
- Apply filters for customer code, reference numbers, dates
- View order details including items and net values

### 3. Bulk Indent — Order Creation
- Select a sales order from search results
- Click "Manage" to navigate to order creation
- Fill in required third-party agent information (if applicable)
- Create the order with proper validation

### 4. Agent Management
- Add multiple agents to an order
- Assign specific quantities to each agent per order item
- Select appropriate transporters with GSTN details
- Validate all allocations before saving

### 5. Direct Indent (WebDynpro)
- Clicking **Direct Indent** on the Home screen opens the SAP WebDynpro app in a new browser tab
- Uses a relative URL so the existing SAP login session is reused — no re-authentication required
- Requires the ICF service `ZSD_CUST_INDENT_DIR_INBAPP` to be active in `SICF`

### 6. Data Validation
- System ensures all required fields are populated
- Prevents over-allocation of quantities
- Validates agent and transporter details
- Provides clear error messages for any issues

## 🔧 Key Components

### Controllers

- **`Home.controller.js`**
  - Entry point controller for the home screen
  - Routes to Bulk Indent (`RouteCustomerIndent`)
  - Opens Direct Indent WebDynpro app in a new tab using relative URL + session reuse parameter

- **`CustomerBulkIndent.controller.js`**
  - Handles sales order search and filtering
  - Manages bulk indent listing with pagination
  - Controls navigation to indent management

- **`ManageBulkIndent.controller.js`**
  - Bulk indent creation and validation logic
  - Agent allocation management
  - Transporter selection and validation
  - Data persistence and error handling

### Views

- **`Home.view.xml`**
  - Home screen with Bulk Indent and Direct Indent buttons

- **`CustomerBulkIndent.view.xml`**
  - Responsive search interface
  - Indent cards with expandable details
  - Created indents listing with grouping

- **`ManageBulkIndent.view.xml`**
  - Indent details display with metrics
  - Agent allocation forms and tables
  - Progress indicators for quantity allocation

### Key Features

- **Dynamic UI Updates**: Real-time quantity calculations and progress bars
- **Data Enrichment**: Automatic lookup of agent and transporter details
- **Hierarchical Order Display**: Grouped orders by sales order
- **LIFO Deletion Policy**: Only latest orders can be deleted first
- **Comprehensive Error Handling**: User-friendly error messages

## 🔌 API Integration

### OData Services Used:

- **`ZSD_CUSTIND_WITHOUTVEHNEW_SRV`**
  - `CustomerOrderSet` - Sales order operations
  - `AgentOrderAllocationSet` - Agent allocation management
  - `AgentDetailsSet` - Agent master data
  - `TransporterDetailsSet` - Transporter information

### Data Flow:
1. Search sales orders from backend
2. Create customer orders with deep entity structure
3. Manage agent allocations with nested items
4. Update used quantities and progress tracking

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork the repository**
2. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes and commit:**
   ```bash
   git commit -m "Add: your feature description"
   ```
4. **Push to the branch:**
   ```bash
   git push origin feature/your-feature-name
   ```
5. **Create a Pull Request**

### Coding Standards
- Follow SAP UI5 best practices
- Use meaningful variable and function names
- Add comments for complex business logic
- Ensure responsive design principles

## 📝 Recent Updates

- ✅ Added Home screen with Bulk Indent and Direct Indent navigation
- ✅ Renamed controllers/views from `CustomerOrder`/`ManageOrder` to `CustomerBulkIndent`/`ManageBulkIndent`
- ✅ Fixed WebDynpro 403 error — switched to relative URL with `sap-wd-run-sc=X` for session reuse
- ✅ Enhanced data validation and error handling
- ✅ Fixed template sharing warnings for better performance
- ✅ Implemented LIFO order deletion policy
- ✅ Added comprehensive agent allocation management
- ✅ Improved UI responsiveness and user experience

## 🐛 Known Issues

- Backend AGENT_NAME field validation (workaround implemented)
- OData READ duplication for allocations (filtering applied)
- CARRIER field leading zeros handling (normalization added)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

For questions or support, please:
- Create an issue in this repository
- Contact the development team
- Check the SAP UI5 documentation for framework-related questions

---

**Built with ❤️ using SAP UI5 and modern web technologies**