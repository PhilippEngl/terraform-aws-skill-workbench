import { Authenticator } from '@aws-amplify/ui-react';
import { WorkbenchPage } from './pages/WorkbenchPage';
import { Header } from './components/Header';

function App() {
  // hideSignUp because self-registration is disabled on the user pool: a demo pool
  // that anyone can join is a demo pool anyone can write skills into.
  return (
    <Authenticator hideSignUp={true}>
      {({ signOut, user }) => (
        <div className="h-screen w-screen overflow-hidden bg-gray-950 flex flex-col">
          <Header
            email={user?.signInDetails?.loginId || ''}
            onSignOut={signOut || (() => {})}
          />
          <WorkbenchPage />
        </div>
      )}
    </Authenticator>
  );
}

export default App;
