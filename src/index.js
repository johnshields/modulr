const express = require("express");
const dotenv = require("dotenv");
const { createClient } = require("@supabase/supabase-js");

dotenv.config();
const app = express();
app.use(express.json());

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_KEY
);

// Load balancer
app.get("/", (req, res) => {
  res.json({ status: "modulr API is live..." });
});

// Equipment endpoints
app.get("/api/items", async (req, res) => {
  const { data, error } = await supabase.from("items").select("*");
  
  if (error) {
    return res.status(500).json({ error: error.message });
  }

  res.json(data);
});

// GET equipment by ID
app.get("/api/items/:id", async (req, res) => {
  const { id } = req.params;

  const { data, error } = await supabase
    .from("items")
    .select("*")
    .eq("id", id)
    .single();

  if (error) {
    return res.status(404).json({ error: error.message });
  }

  res.json(data);
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`modulr API running on port ${PORT}`));
