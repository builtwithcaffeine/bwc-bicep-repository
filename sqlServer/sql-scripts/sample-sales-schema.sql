-- =============================================================
-- Sample Sales Database Schema
-- Idempotent: safe to run multiple times
-- =============================================================

IF SCHEMA_ID(N'sales') IS NULL
    EXEC(N'CREATE SCHEMA sales');
GO

-- =============================================================
-- Tables
-- =============================================================

IF OBJECT_ID(N'sales.Customer', N'U') IS NULL
BEGIN
    CREATE TABLE sales.Customer
    (
        CustomerId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customer PRIMARY KEY,
        FirstName       NVARCHAR(100) NOT NULL,
        LastName        NVARCHAR(100) NOT NULL,
        Email           NVARCHAR(256) NOT NULL,
        Phone           NVARCHAR(50)  NULL,
        CreatedUtc      DATETIME2(0)  NOT NULL CONSTRAINT DF_Customer_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_Customer_Email UNIQUE (Email)
    );
END
GO

IF OBJECT_ID(N'sales.Product', N'U') IS NULL
BEGIN
    CREATE TABLE sales.Product
    (
        ProductId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Product PRIMARY KEY,
        Sku             NVARCHAR(50)  NOT NULL,
        Name            NVARCHAR(200) NOT NULL,
        Description     NVARCHAR(1000) NULL,
        UnitPrice       DECIMAL(10,2) NOT NULL CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0),
        IsActive        BIT           NOT NULL CONSTRAINT DF_Product_IsActive DEFAULT (1),
        CONSTRAINT UQ_Product_Sku UNIQUE (Sku)
    );
END
GO

IF OBJECT_ID(N'sales.SalesOrder', N'U') IS NULL
BEGIN
    CREATE TABLE sales.SalesOrder
    (
        OrderId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalesOrder PRIMARY KEY,
        CustomerId      INT           NOT NULL,
        OrderDate       DATETIME2(0)  NOT NULL CONSTRAINT DF_SalesOrder_OrderDate DEFAULT (SYSUTCDATETIME()),
        Status          NVARCHAR(20)  NOT NULL CONSTRAINT DF_SalesOrder_Status   DEFAULT (N'Pending'),
        TotalAmount     DECIMAL(12,2) NOT NULL CONSTRAINT DF_SalesOrder_Total    DEFAULT (0),
        CONSTRAINT FK_SalesOrder_Customer FOREIGN KEY (CustomerId) REFERENCES sales.Customer(CustomerId),
        CONSTRAINT CK_SalesOrder_Status CHECK (Status IN (N'Pending', N'Paid', N'Shipped', N'Cancelled'))
    );
END
GO

IF OBJECT_ID(N'sales.SalesOrderLine', N'U') IS NULL
BEGIN
    CREATE TABLE sales.SalesOrderLine
    (
        OrderLineId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalesOrderLine PRIMARY KEY,
        OrderId         INT           NOT NULL,
        ProductId       INT           NOT NULL,
        Quantity        INT           NOT NULL CONSTRAINT CK_OrderLine_Qty CHECK (Quantity > 0),
        UnitPrice       DECIMAL(10,2) NOT NULL,
        LineTotal       AS (Quantity * UnitPrice) PERSISTED,
        CONSTRAINT FK_OrderLine_Order   FOREIGN KEY (OrderId)   REFERENCES sales.SalesOrder(OrderId) ON DELETE CASCADE,
        CONSTRAINT FK_OrderLine_Product FOREIGN KEY (ProductId) REFERENCES sales.Product(ProductId)
    );
END
GO

-- =============================================================
-- Indexes
-- =============================================================

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SalesOrder_CustomerId' AND object_id = OBJECT_ID(N'sales.SalesOrder'))
    CREATE INDEX IX_SalesOrder_CustomerId ON sales.SalesOrder (CustomerId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SalesOrderLine_OrderId' AND object_id = OBJECT_ID(N'sales.SalesOrderLine'))
    CREATE INDEX IX_SalesOrderLine_OrderId ON sales.SalesOrderLine (OrderId);
GO

-- =============================================================
-- Seed data (only if tables empty)
-- =============================================================

IF NOT EXISTS (SELECT 1 FROM sales.Customer)
BEGIN
    INSERT INTO sales.Customer (FirstName, LastName, Email, Phone) VALUES
        (N'Alice',   N'Walker',  N'alice.walker@example.com',   N'+44 20 7946 0001'),
        (N'Bob',     N'Smith',   N'bob.smith@example.com',      N'+44 20 7946 0002'),
        (N'Charlie', N'Jones',   N'charlie.jones@example.com',  N'+44 20 7946 0003');
END
GO

IF NOT EXISTS (SELECT 1 FROM sales.Product)
BEGIN
    INSERT INTO sales.Product (Sku, Name, Description, UnitPrice) VALUES
        (N'SKU-0001', N'Coffee Beans 1kg',     N'Single origin arabica beans',  18.50),
        (N'SKU-0002', N'Ceramic Mug',          N'350ml branded ceramic mug',     9.99),
        (N'SKU-0003', N'Espresso Machine',     N'Entry-level home espresso',   249.00),
        (N'SKU-0004', N'Milk Frother',         N'Handheld battery frother',     14.75);
END
GO

IF NOT EXISTS (SELECT 1 FROM sales.SalesOrder)
BEGIN
    DECLARE @cust1 INT = (SELECT TOP 1 CustomerId FROM sales.Customer ORDER BY CustomerId);
    DECLARE @prod1 INT = (SELECT ProductId FROM sales.Product WHERE Sku = N'SKU-0001');
    DECLARE @prod2 INT = (SELECT ProductId FROM sales.Product WHERE Sku = N'SKU-0002');

    INSERT INTO sales.SalesOrder (CustomerId, Status, TotalAmount) VALUES (@cust1, N'Paid', 0);
    DECLARE @orderId INT = SCOPE_IDENTITY();

    INSERT INTO sales.SalesOrderLine (OrderId, ProductId, Quantity, UnitPrice) VALUES
        (@orderId, @prod1, 2, 18.50),
        (@orderId, @prod2, 1,  9.99);

    UPDATE o
        SET TotalAmount = (SELECT SUM(LineTotal) FROM sales.SalesOrderLine WHERE OrderId = o.OrderId)
    FROM sales.SalesOrder o
    WHERE o.OrderId = @orderId;
END
GO

-- =============================================================
-- View
-- =============================================================

IF OBJECT_ID(N'sales.vOrderSummary', N'V') IS NOT NULL
    DROP VIEW sales.vOrderSummary;
GO

CREATE VIEW sales.vOrderSummary
AS
SELECT
    o.OrderId,
    o.OrderDate,
    o.Status,
    c.CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    c.Email,
    o.TotalAmount,
    (SELECT COUNT(*) FROM sales.SalesOrderLine l WHERE l.OrderId = o.OrderId) AS LineCount
FROM sales.SalesOrder o
INNER JOIN sales.Customer c ON c.CustomerId = o.CustomerId;
GO
