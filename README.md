# modulr 🎛️

A backend API for a mock rental service, built with Node.js and Supabase to simulate real-world workflows. Implements RESTful routes for gear management with PostgreSQL integration, structured using MVC patterns and tested with Postman.

## 🧰 Development Environment 

- **Node.js** / **Express**
- **Supabase** (PostgreSQL)

## 📁 API Directory & File Structure 
```
modulr/
├── src/
│ ├── controllers/
│ │ └── gearController.js
│ ├── models/
│ │ └── gearModel.js
│ ├── routes/
│ │ └── gearRoutes.js
│ ├── services/
│ │ └── supabaseClient.js
│ └── server.js
├── .env
└── package.json
```

---

## 🚀 How to Run 

### Requirements

- [Git](https://git-scm.com/downloads)
- [Supabase](https://supabase.com/)
- [Node.js & NPM](https://nodejs.org/)
- [Postman](https://www.postman.com/downloads/) (for manual API testing)

### ⚙️ Setup & Run

#### Open a directory in Command-Line and enter:
```bash
$ git clone https://github.com/johnshields/modulr.git
```

#### Create a .env file:

```
SUPABASE_URL=your_supabase_url
SUPABASE_KEY=your_supabase_anon_key
```

#### SQL script located here [sql/modulr_db.sql](works/sql/modulr_db.sql)

#### Run API

```bash
$ cd modulr/
$ npm install
$ npm run dev
```

* The API will listen on: http://localhost:8080/
* View API Swagger docs: http://localhost:8080/api/swagger

📦 API Endpoints

- `GET /api/gear` - List all gear
- `GET /api/gear/:id` - Get gear by ID
- `POST /api/gear` - Add new gear
- `PUT /api/gear/:id` - Update gear
- `DELETE /api/gear/:id` - Delete gear

***
