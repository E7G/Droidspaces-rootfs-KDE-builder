// SPDX-License-Identifier: MIT
/* Minimal PID 1 for the WinLite container: reap children and forward signals. */

#define _GNU_SOURCE

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t child_pid = -1;

static void forward_signal(int signo)
{
    pid_t pid = (pid_t)child_pid;

    if (pid > 0 && signo != SIGCHLD) {
        /* The child owns a process group, so descendants receive shutdown. */
        (void)kill(-pid, signo);
    }
}

static int install_handlers(void)
{
    static const int signals[] = {
        SIGHUP, SIGINT, SIGQUIT, SIGUSR1, SIGUSR2, SIGTERM,
        SIGCONT, SIGTSTP, SIGTTIN, SIGTTOU, SIGWINCH, SIGCHLD,
    };
    struct sigaction action = {
        .sa_handler = forward_signal,
        .sa_flags = SA_RESTART,
    };

    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i) {
        if (sigaction(signals[i], &action, NULL) < 0) {
            return -1;
        }
    }
    return 0;
}

static void reset_child_handlers(void)
{
    static const int signals[] = {
        SIGHUP, SIGINT, SIGQUIT, SIGUSR1, SIGUSR2, SIGTERM,
        SIGCONT, SIGTSTP, SIGTTIN, SIGTTOU, SIGWINCH, SIGCHLD,
    };
    struct sigaction action = {
        .sa_handler = SIG_DFL,
    };

    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i) {
        (void)sigaction(signals[i], &action, NULL);
    }
}

int main(int argc, char **argv)
{
    int main_status = 0;
    int main_exited = 0;
    pid_t pid;

    if (argc < 2) {
        fprintf(stderr, "usage: %s command [args...]\n", argv[0]);
        return 64;
    }

    if (prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) < 0 && getpid() != 1) {
        perror("droidspaces-tini: PR_SET_CHILD_SUBREAPER");
        return 1;
    }
    if (install_handlers() < 0) {
        perror("droidspaces-tini: sigaction");
        return 1;
    }

    pid = fork();
    if (pid < 0) {
        perror("droidspaces-tini: fork");
        return 1;
    }
    if (pid == 0) {
        reset_child_handlers();
        (void)setpgid(0, 0);
        execvp(argv[1], &argv[1]);
        perror("droidspaces-tini: execvp");
        _exit(errno == ENOENT ? 127 : 126);
    }

    child_pid = pid;
    (void)setpgid(pid, pid);

    while (!main_exited) {
        int status;
        pid_t reaped = waitpid(-1, &status, 0);

        if (reaped < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == ECHILD) {
                break;
            }
            perror("droidspaces-tini: waitpid");
            return 1;
        }
        if (reaped == pid) {
            main_status = status;
            main_exited = 1;
            child_pid = -1;
        }
    }

    /* Collect already-dead adopted children without adding a polling loop. */
    while (waitpid(-1, NULL, WNOHANG) > 0) {
    }

    if (WIFEXITED(main_status)) {
        return WEXITSTATUS(main_status);
    }
    if (WIFSIGNALED(main_status)) {
        return 128 + WTERMSIG(main_status);
    }
    return 1;
}
