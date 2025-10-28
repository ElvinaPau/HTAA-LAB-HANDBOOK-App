const express = require("express");
const cors = require("cors");
require("dotenv").config();

const pool = require("./db");

const app = express();

app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;

// Routes
app.get("/api/categories", async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM categories ORDER BY position ASC");
    res.json(result.rows);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: "Server error" });
  }
});

app.get("/api/lab-tests", async (req, res) => {
  const categoryName = req.query.category;
  if (!categoryName) {
    return res.status(400).json({ error: "Missing category parameter" });
  }

  try {
    const result = await pool.query(
      `SELECT lt.* FROM lab_tests lt
       JOIN categories c ON lt.category_id = c.id
       WHERE c.category_name = $1
       ORDER BY lt.position ASC`,
      [categoryName]
    );
    res.json(result.rows);
  } catch (err) {
    console.error("Error fetching lab tests:", err.message);
    res.status(500).json({ error: "Failed to get lab tests" });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
