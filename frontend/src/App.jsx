import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import ProtectedRoute from './routes/ProtectedRoute'
import RoleRedirect from './routes/RoleRedirect'

import Login from './pages/Login'
import Register from './pages/Register'
import CustomerHome from './pages/customer/CustomerHome'
import RestaurantHome from './pages/restaurant/RestaurantHome'
import RiderHome from './pages/rider/RiderHome'
import RestaurantDetail from './pages/customer/RestaurantDetail'

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          {/* Public routes */}
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />

          {/* Sau khi login, "/" sẽ tự điều hướng theo role */}
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <RoleRedirect />
              </ProtectedRoute>
            }
          />

          {/* Route riêng cho từng role */}
          <Route
            path="/customer"
            element={
              <ProtectedRoute allowedRoles={['customer']}>
                <CustomerHome />
              </ProtectedRoute>
            }
          />
          <Route
            path="/customer/restaurant/:id"
            element={
              <ProtectedRoute allowedRoles={['customer']}>
                <RestaurantDetail />
              </ProtectedRoute>
            }
          />

          <Route
            path="/restaurant"
            element={
              <ProtectedRoute allowedRoles={['restaurant']}>
                <RestaurantHome />
              </ProtectedRoute>
            }
          />

          <Route
            path="/rider"
            element={
              <ProtectedRoute allowedRoles={['rider']}>
                <RiderHome />
              </ProtectedRoute>
            }
          />

          {/* Route không khớp -> về "/" (sẽ tự redirect theo role) */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}

export default App